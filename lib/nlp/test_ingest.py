"""Checks for the PDF-shaping heuristics, which are the parts most likely to
misread a real book. Run with: .venv/bin/python lib/nlp/test_ingest.py"""

import sys

from ingest import (
    is_sentence_like,
    is_unreadable,
    join_lines,
    looks_like_heading,
    looks_like_stamp,
)

BODY = 10.0

HEADINGS = [
    ("Capítulo 1", BODY),
    ("Capítulo 12.", BODY),
    ("CAPÍTULO IV", BODY),
    ("Epílogo", BODY),
    ("Prólogo", BODY),
    ("LA PUERTA DE LOS TRES CERROJOS", BODY),
    ("El cementerio de los libros olvidados", 14.0),
]

# Every one of these was previously swallowed as a heading.
NOT_HEADINGS = [
    # The riddle box, set in large all-caps display type.
    ("«IMAGINAOS UNA CALLE POR LA QUE CIRCULA UN COCHE OSCURO,", 13.0),
    ("SIN LUCES. TODAS LAS FAROLAS DE LA CALLE ESTÁN APAGADAS.", 13.0),
    ("¿CÓMO HA CONSEGUIDO VERLO?»", 13.0),
    ("—¡TODO ESTO ES ABSURDO! ¿NO VEIS QUE NO ES", 13.0),
    # Front matter set slightly larger than the body.
    ("Gracias por adquirir este eBook", 12.0),
    ("Visita Planetadelibros.com y descubre una", 12.0),
    ("¡Regístrate y accede a contenidos", 12.0),
    # Ordinary prose.
    ("Todavía recuerdo aquel amanecer en que mi padre me llevó.", BODY),
    ("Unas cuantas manos se alzaron.", BODY),
]


def check(label, condition):
    print(f"{'ok  ' if condition else 'FAIL'} {label}")
    return condition


def main():
    passed = True

    for text, size in HEADINGS:
        passed &= check(f"heading: {text!r}", looks_like_heading(text, size, BODY))

    for text, size in NOT_HEADINGS:
        passed &= check(f"prose:   {text[:46]!r}", not looks_like_heading(text, size, BODY))

    passed &= check("comma means prose", is_sentence_like("UNA CALLE, OSCURA"))
    passed &= check("label is not prose", is_sentence_like("LA PUERTA") is False)

    # A line introducing what follows is prose, however it is styled.
    passed &= check("colon means prose", not looks_like_heading(
        "Luego encendió las luces de nuevo y les propuso un enigma:", 14.0, BODY))

    # Decorative fonts with no encoding extract as runs of question marks.
    passed &= check("unmapped glyphs dropped", is_unreadable("? ? ? ?"))
    passed &= check("replacement chars dropped", is_unreadable("\ufffd\ufffd\ufffd"))
    passed &= check("scene break kept", not is_unreadable("* * *"))
    passed &= check("dash kept", not is_unreadable("—"))
    passed &= check("real question kept", not is_unreadable("¿Cómo ha conseguido verlo?"))
    passed &= check("short question kept", not is_unreadable("¿Qué?"))

    # Source stamps that interrupt the prose of re-hosted PDFs.
    passed &= check("stamp: OceanofPDF.com", looks_like_stamp("OceanofPDF.com"))
    passed &= check("stamp: www", looks_like_stamp("www.epublibre.org"))
    passed &= check("stamp: url", looks_like_stamp("https://example.com/book"))
    passed &= check("prose is not a stamp", not looks_like_stamp(
        "Todavía recuerdo aquel amanecer en que mi padre me llevó a visitar."))
    passed &= check("a sentence mentioning a site is not a stamp", not looks_like_stamp(
        "Lo encontré en Planetadelibros.com esa misma tarde de verano."))

    # A word broken across a line break is healed; a normal break becomes a space.
    passed &= check("dehyphenation", join_lines(
        [{"text": "conse-"}, {"text": "guido"}]) == "conseguido")
    passed &= check("line join", join_lines(
        [{"text": "una calle"}, {"text": "oscura"}]) == "una calle oscura")

    print("\nall passed" if passed else "\nFAILURES")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
