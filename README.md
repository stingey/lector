# Lector

Read Spanish books from PDFs, tap any word for a contextual translation, and every
conjugation of the words you save lights up for the rest of the book.

## The idea

The hard-sounding part of this app is recognizing that `dijeron`, `diga`, and
`diciéndomelo` are all the same word you are trying to learn. That turns out not to
be an AI problem at all.

At upload time, spaCy resolves the lemma and full morphology of every word in the
book, and those get stored in Postgres. After that:

- Highlighting saved words is an indexed database lookup. Instant, free, and it
  works on every page without a single model call.
- The hover tooltip ("preterite, 3rd person singular, from `decir`") is a stored
  row, not a generated guess.
- The language model is left with the one job it is genuinely good at: reading the
  sentence and saying what the word means *there*.

Saving one verb typically lights up 15 to 20 distinct forms across a novel.

## Reading

- Left and right arrow keys turn the page. `Escape` closes an open word card.
- `A−` and `A+` change the reading size. The column width is set in `em`, so it grows
  with the type and the line length stays at a comfortable character count instead of
  the page just getting longer.
- Any word can be bookmarked from its card. A bookmark is a *place*, not a word: it
  marks that one occurrence, unlike the word bank, which keys off the lemma and so
  highlights every conjugation. Bookmarked words carry a ribbon while reading, and the
  bookmarks list for a book links straight back to the word itself.
- Each library row carries a **Continue from bookmark** button when you have a mark in
  that book, and a plain **Continue** when you do not, so the button says where it goes
  rather than leaving you to remember. It goes to your newest bookmark if there is one,
  otherwise the page you last turned to, which is recorded automatically on every page
  turn. `ResumePoints` resolves that for a whole library in a few queries.
- The bookmark wins even if you have since read past it, because the button names it.
  Nothing is lost either way: the row also shows the position it will take you to
  ("page 41 of 120").

## Stack

- Rails 8, Hotwire, Postgres, Solid Queue
- Python at ingest time only: [PyMuPDF](https://pymupdf.readthedocs.io) for text
  and images in reading order, [spaCy](https://spacy.io) `es_core_news_md` for
  lemmas and morphology
- [`fsrs_ruby`](https://github.com/ondrejrohon/fsrs_ruby) for spaced repetition
- No Python service runs in production. `lib/nlp/ingest.py` is a CLI that streams
  JSONL, invoked from a background job.

## Setup

Requires Ruby 3.2+, Postgres, and Python 3.11+.

```bash
bundle install
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
bin/rails db:prepare
bin/rails db:seed        # creates a development login
bin/rails server
```

Then sign in with `reader@example.com` / `password`, upload a Spanish PDF, and wait
about a minute for a full novel.

Run the background worker in a second terminal so uploads process:

```bash
bin/jobs
```

### Contextual translation (optional)

The app is fully usable without an API key: grammar, the word bank, highlighting,
and the quiz all work offline. Set a key to turn on contextual meanings.

```bash
export TRANSLATOR_API_KEY=sk-...
export TRANSLATOR_MODEL=gpt-5-mini        # optional
export TRANSLATOR_PROVIDER=openai         # or anthropic
export TRANSLATOR_BASE_URL=...            # optional, for an OpenAI-compatible gateway
```

`openai` works with anything speaking the chat-completions dialect, which includes
Gemini's compatibility endpoint, Groq, and OpenRouter. Every lookup is cached by
(lemma, word form, sentence), so a given word in a given sentence is paid for once
and then served from Postgres forever. Expect a small fraction of a cent per new
lookup.

## How ingest works

```
PDF -> PyMuPDF -> blocks and images in reading order
                  headers/footers dropped, hyphenation healed,
                  paragraphs rejoined across page breaks
    -> spaCy   -> lemma, part of speech, morphology, sentence boundaries
    -> JSONL   -> Rails bulk-inserts blocks, sentences, tokens, lemmas
```

A 273-page novel comes out as roughly 2,200 blocks and 158,000 tokens in about 30
seconds. Only word tokens get rows; punctuation stays in the block text and is
reproduced from character offsets, so a paragraph renders back byte-for-byte.

Useful environment variables:

- `INGEST_MAX_PAGES` caps pages, which is handy while iterating
- `PYTHON_BIN` overrides the interpreter (defaults to `.venv/bin/python`, then `python3`)
- `SPACY_MODEL` defaults to `es_core_news_md`

## Testing

```bash
bin/rails test                          # models, controllers, and full request flows
bin/rails test:system                   # drives a real browser against real PDFs
.venv/bin/python lib/nlp/test_ingest.py # the PDF-shaping heuristics
```

System tests are skipped automatically when the sample PDFs or the Python environment
are missing. They cover a plain novel and an illustrated one, because illustrated
books break assumptions a novel never exercises.

The heuristics in `lib/nlp/ingest.py` decide what counts as a heading, a watermark,
or unreadable glyph junk, and they are the likeliest thing to misread a new book.
`test_ingest.py` pins them against real lines taken from books that broke them.

## Importing an existing deck

```bash
# In langflash:
rails runner 'puts Card.all.map { |c| [c.spanish_text, c.english_text, c.part_of_speech].to_csv }.join'

# Here:
rake import:langflash EMAIL=you@example.com FILE=cards.csv
```

Imported words attach to existing lemmas where possible, so they start highlighting
in books you have already ingested.

## Deploying to Heroku

Python and Ruby coexist through two buildpacks. Ruby must be last so Rails stays
the primary language.

```bash
heroku create
heroku buildpacks:add --index 1 heroku/python
heroku buildpacks:add heroku/ruby
heroku addons:create heroku-postgresql:essential-0
heroku config:set TRANSLATOR_API_KEY=sk-... RAILS_MASTER_KEY=$(cat config/master.key)
git push heroku main
heroku ps:scale web=1 worker=1
```

`requirements.txt` installs spaCy and the Spanish model, roughly 50 MB, well inside
the slug limit. Uploaded PDFs and extracted images need durable storage, so
configure Active Storage for S3 before relying on it: Heroku's filesystem is
ephemeral and anything written to disk disappears when a dyno restarts.

## Known limits

- Scanned PDFs have no text layer and are rejected. OCR is not implemented yet.
- Words drawn inside illustrations are not extracted, which matters for some
  children's and illustrated books.
- Paragraph reconstruction is heuristic. Front matter and title pages are the
  roughest part; body prose comes out clean. Heading detection is deliberately
  conservative, because a missed heading is just a plain paragraph while a false one
  swallows real prose. Publisher boilerplate set in large type is still sometimes
  marked as a heading, which is cosmetic only: heading words stay tappable.
- The Spanish lemmatizer occasionally mislabels proper nouns. Any entry's lemma can
  be corrected from the word bank.
- Re-uploading or re-ingesting a book discards its bookmarks, because every character
  offset they point at is recomputed. Saved words survive: they are attached to lemmas
  rather than to positions.
- Reader pages are a fixed 40 blocks, so a page break can land mid-scene. Breaking at
  chapter boundaries instead would be the improvement.
