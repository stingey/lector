#!/usr/bin/env python3
"""Turn a Spanish book PDF into annotated, reflowable blocks.

Emits JSONL on stdout so a whole novel never has to be held in memory on either
side of the pipe: the first line is a meta object, every subsequent line is one
block.

    python ingest.py BOOK.pdf --images-dir DIR [--max-pages N] [--model NAME]

Blocks come out in reading order and carry, for every word, the lemma and
morphological features spaCy assigned it. Those lemmas are what let a single
saved word match every conjugation of itself later on.
"""

import argparse
import hashlib
import json
import os
import re
import sys
import unicodedata
from collections import Counter

import pymupdf

# A running header sitting on this fraction of pages is furniture, not prose.
HEADER_ZONE = 0.07
FOOTER_ZONE = 0.93
REPEAT_THRESHOLD = 0.25

# Images smaller than this are rules, bullets, and logos rather than illustrations.
MIN_IMAGE_PIXELS = 6000
MIN_IMAGE_SIDE = 40

TERMINAL_PUNCTUATION = ('.', '!', '?', '"', '»', '"', '…', ':', '*')

# A chapter title is short. Prose that happens to be set in display type is not, and
# this is the first gate that keeps callouts and riddles out of the heading path.
HEADING_MAX_CHARS = 60

LIGATURES = {
    "\ufb00": "ff", "\ufb01": "fi", "\ufb02": "fl", "\ufb03": "ffi",
    "\ufb04": "ffl", "\u2019": "'", "\u2018": "'", "\u00ad": "",
}


def clean_text(value):
    """Normalize unicode oddities that PDF text layers are full of."""
    value = unicodedata.normalize("NFC", value)
    for bad, good in LIGATURES.items():
        value = value.replace(bad, good)
    value = value.replace("\t", " ")
    return re.sub(r"[ \u00a0]{2,}", " ", value).strip()


def normalize_for_repeat(value):
    """Collapse a line to a shape, so 'Page 12' and 'Page 13' compare equal."""
    value = re.sub(r"\d+", "#", value.lower())
    return re.sub(r"\s+", " ", value).strip()


# Pirated and re-hosted PDFs stamp a source domain onto many pages, often mid-page
# rather than in the margins where running headers live. Matched by shape so it needs
# no list of known sites, and required to repeat before anything is dropped: a URL
# mentioned once may well belong to the book.
URL_SHAPE = re.compile(r"(https?://|www\.|\w+\.(com|net|org|info|io|me|es)\b)", re.I)
WATERMARK_MIN_PAGES = 5
WATERMARK_MAX_CHARS = 40


def looks_like_stamp(value):
    return len(value) <= WATERMARK_MAX_CHARS and bool(URL_SHAPE.search(value))


def is_unreadable(text):
    """Drop lines that are mostly glyphs the PDF could not map to characters.

    Decorative and hand-lettered fonts often have no usable encoding, so their text
    layer extracts as runs of "?" or U+FFFD. There is nothing to read or translate in
    those, and left in they show up as stray "? ? ? ?" paragraphs. Lines that merely
    contain punctuation, like a "* * *" scene break, still have no letters but are not
    junk, so only the unmapped markers count against a line.
    """
    dense = re.sub(r"\s+", "", text)
    if not dense:
        return True

    unmapped = sum(character in "?\ufffd" for character in dense)
    if unmapped == 0:
        return False

    return unmapped / len(dense) > 0.5 and not re.search(r"[^\W\d_]", text)


def is_page_number(value):
    stripped = value.strip(" .-–—[]()")
    if not stripped:
        return True
    if stripped.isdigit():
        return True
    return bool(re.fullmatch(r"[ivxlcdm]+", stripped.lower()))


def line_text(line):
    return "".join(span["text"] for span in line.get("spans", ()))


def line_size(line):
    spans = [s for s in line.get("spans", ()) if s.get("text", "").strip()]
    if not spans:
        return 0.0
    return max(round(s.get("size", 0.0), 1) for s in spans)


def survey(doc, page_limit):
    """First pass: find the running headers/footers, source stamps, and body size."""
    repeats = Counter()
    stamps = Counter()
    sizes = Counter()

    for page_index in range(page_limit):
        page = doc[page_index]
        height = page.rect.height or 1.0
        for block in page.get_text("dict", sort=True).get("blocks", ()):
            if block.get("type") != 0:
                continue
            for line in block.get("lines", ()):
                text = clean_text(line_text(line))
                if not text:
                    continue

                size = line_size(line)
                if size:
                    sizes[size] += len(text)

                if looks_like_stamp(text):
                    stamps[normalize_for_repeat(text)] += 1

                relative_y = line["bbox"][1] / height
                if relative_y <= HEADER_ZONE or relative_y >= FOOTER_ZONE:
                    repeats[normalize_for_repeat(text)] += 1

    minimum = max(2, int(page_limit * REPEAT_THRESHOLD))
    furniture = {shape for shape, count in repeats.items() if count >= minimum}

    # Kept separate from furniture because a stamp is dropped wherever it sits on the
    # page, while a running header is only furniture when it appears in the margin.
    watermarks = {
        shape for shape, count in stamps.items()
        if count >= min(WATERMARK_MIN_PAGES, page_limit)
    }

    body_size = sizes.most_common(1)[0][0] if sizes else 0.0
    return furniture, watermarks, body_size


def gather_lines(page, furniture, watermarks):
    """Second pass: page content as (kind, payload) pairs in reading order."""
    height = page.rect.height or 1.0
    items = []

    for block in page.get_text("dict", sort=True).get("blocks", ()):
        if block.get("type") == 1:
            items.append(("image", block))
            continue

        lines = []
        for line in block.get("lines", ()):
            text = clean_text(line_text(line))
            if not text:
                continue

            if is_unreadable(text):
                continue

            shape = normalize_for_repeat(text)
            if shape in watermarks:
                continue

            relative_y = line["bbox"][1] / height
            edge = relative_y <= HEADER_ZONE or relative_y >= FOOTER_ZONE
            if edge and (shape in furniture or is_page_number(text)):
                continue

            # Title pages often fake a drop shadow by drawing the same string twice
            # at almost the same spot. Keep one copy.
            if lines and lines[-1]["text"] == text:
                continue

            lines.append({"text": text, "size": line_size(line), "x": line["bbox"][0]})

        if lines:
            items.append(("text", lines))

    return items


def join_lines(lines):
    """Stitch physical lines into prose, healing words split by a line break."""
    out = ""
    for raw in lines:
        text = raw["text"]
        if not out:
            out = text
            continue

        if out.endswith(("-", "\u2010", "\u2011")) and text[:1].islower():
            out = out[:-1] + text
        else:
            out = out + " " + text

    return out.strip()


def is_sentence_like(text):
    """True when the text reads as prose rather than as a label.

    Punctuation is a far better signal than styling. Books set callouts, riddles, and
    epigraphs in large all-caps display type that looks exactly like a chapter title
    to a font-size test, but no chapter title contains a comma, ends in a colon
    introducing what follows, or holds a mid-string full stop.
    """
    if re.search(r"[,;!?…]", text):
        return True
    if re.search(r"\.\s+\S", text):
        return True
    return bool(re.search(r"[.:»\"]$", text))


def looks_like_heading(text, size, body_size):
    """Conservative on purpose.

    A missed heading is merely a plain paragraph, still readable and still tappable.
    A false heading swallows real prose into a label, so the bar is set high and
    anything sentence-shaped is refused outright.
    """
    if len(text) > HEADING_MAX_CHARS or len(text) < 2:
        return False

    # Explicit chapter markers are allowed to keep their punctuation ("Capítulo 1.").
    if re.match(r"^(cap[ií]tulo|parte|libro|ep[ií]logo|pr[oó]logo)\b[\s\d.:ivxlcdm]*$", text, re.I):
        return True

    if is_sentence_like(text):
        return False

    if body_size and size >= body_size * 1.35:
        return True

    return bool(text == text.upper() and re.search(r"[A-ZÁÉÍÓÚÑ]", text))


def image_payload(block, images_dir, seen):
    data = block.get("image")
    if not data:
        return None

    width = block.get("width") or 0
    height = block.get("height") or 0
    if width < MIN_IMAGE_SIDE or height < MIN_IMAGE_SIDE:
        return None
    if width * height < MIN_IMAGE_PIXELS:
        return None

    checksum = hashlib.sha256(data).hexdigest()
    if checksum not in seen:
        extension = (block.get("ext") or "png").lower()
        filename = f"{checksum}.{extension}"
        with open(os.path.join(images_dir, filename), "wb") as handle:
            handle.write(data)
        seen[checksum] = filename

    return {
        "checksum": checksum,
        "file": seen[checksum],
        "width": width,
        "height": height,
    }


def build_paragraphs(doc, furniture, watermarks, body_size, page_limit, images_dir):
    """Yield ordered blocks, merging paragraphs that run across pages."""
    seen_images = {}
    pending = None  # a paragraph still waiting for its ending

    for page_index in range(page_limit):
        page_number = page_index + 1

        for kind, payload in gather_lines(doc[page_index], furniture, watermarks):
            if kind == "image":
                image = image_payload(payload, images_dir, seen_images)
                if not image:
                    continue
                if pending:
                    yield pending
                    pending = None
                yield {"kind": "image", "page": page_number, "text": "", "image": image}
                continue

            text = join_lines(payload)
            if not text:
                continue

            size = max(line["size"] for line in payload)
            if looks_like_heading(text, size, body_size):
                if pending:
                    yield pending
                    pending = None
                yield {"kind": "heading", "page": page_number, "text": text}
                continue

            if pending is None:
                pending = {"kind": "paragraph", "page": page_number, "text": text}
            elif pending["text"].endswith(TERMINAL_PUNCTUATION):
                # The previous paragraph closed cleanly, so this is a new one.
                yield pending
                pending = {"kind": "paragraph", "page": page_number, "text": text}
            else:
                # Mid-sentence: the paragraph was split by a column or page break.
                pending["text"] = join_lines([
                    {"text": pending["text"]}, {"text": text}
                ])

    if pending:
        yield pending


def fix_lemma(lemma, pos):
    """Repair the one systematic error the Spanish lemmatizer makes.

    It sometimes carries an accent from the inflected form onto the infinitive
    ("caminábamos" -> "caminár"). No Spanish infinitive ends in an accented
    vowel plus r, so this is always wrong and always safe to undo.
    """
    if pos in ("VERB", "AUX") and len(lemma) > 2 and lemma.endswith("r"):
        stem, vowel = lemma[:-2], lemma[-2]
        replacement = {"á": "a", "é": "e", "í": "i"}.get(vowel)
        if replacement:
            return f"{stem}{replacement}r"

    return lemma


def annotate(doc):
    """Sentence-split one analyzed paragraph and keep only its word tokens.

    Offsets are relative to the paragraph text, so the reader can rebuild the
    paragraph verbatim and wrap each word in place without touching punctuation.
    """
    sentences = []

    for index, sent in enumerate(doc.sents):
        tokens = [
            {
                "surface": token.text,
                "lemma": fix_lemma(token.lemma_.lower(), token.pos_),
                "pos": token.pos_,
                "morph": token.morph.to_dict(),
                "start": token.idx,
                "end": token.idx + len(token.text),
            }
            for token in sent
            if token.is_alpha
        ]

        if not tokens:
            continue

        sentences.append({
            "position": index,
            "start": sent.start_char,
            "end": sent.end_char,
            "text": sent.text.strip(),
            "tokens": tokens,
        })

    return sentences


def emit(payload):
    sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pdf")
    parser.add_argument("--images-dir", required=True)
    parser.add_argument("--max-pages", type=int)
    parser.add_argument("--model", default="es_core_news_md")
    args = parser.parse_args()

    os.makedirs(args.images_dir, exist_ok=True)

    import spacy  # imported late: it costs a second and argparse may bail first

    nlp = spacy.load(args.model, exclude=["ner"])
    nlp.max_length = 2_000_000

    with pymupdf.open(args.pdf) as doc:
        page_limit = min(args.max_pages or doc.page_count, doc.page_count)
        metadata = doc.metadata or {}

        furniture, watermarks, body_size = survey(doc, page_limit)

        emit({
            "type": "meta",
            "page_count": doc.page_count,
            "pages_read": page_limit,
            "title": clean_text(metadata.get("title") or ""),
            "author": clean_text(metadata.get("author") or ""),
            "body_font_size": body_size,
        })

        blocks = build_paragraphs(doc, furniture, watermarks, body_size, page_limit, args.images_dir)

        # nlp.pipe batches the model over many blocks at once, which is several times
        # faster than calling it per block. Images go through the same buffer even
        # though they need no analysis: emitting them early would float every
        # illustration ahead of the text still waiting in the buffer, and their
        # position in the flow is what marks chapters in illustrated books.
        buffer = []
        BATCH = 200

        def flush():
            texts = [block["text"] for block in buffer if block["kind"] != "image"]
            analyzed = nlp.pipe(texts, batch_size=64)

            for block in buffer:
                block["sentences"] = [] if block["kind"] == "image" else annotate(next(analyzed))
                block["type"] = "block"
                emit(block)

            buffer.clear()

        for block in blocks:
            buffer.append(block)
            if len(buffer) >= BATCH:
                flush()

        flush()


if __name__ == "__main__":
    main()
