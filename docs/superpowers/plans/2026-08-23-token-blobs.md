# Token Blobs Implementation Plan

> **For agentic workers:** Implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Run the full suite at the end of every task and commit before starting the next one.

**Goal:** Stop storing one database row per word. Move each block's words into a single JSONB array on `blocks`, and serve the aggregates that used to scan `tokens` from a small per-book rollup table.

**Architecture:** `Token` stops being an ActiveRecord model and becomes a value object read out of `blocks.words`. Identity moves from an integer primary key to the pair `(block, position)`, rendered `"<block_id>-<position>"` in URLs and `token_<block_id>_<position>` in DOM ids, so bookmarks and word-bank provenance stay addressable. Everything that needs "how often does this lemma appear in this book, in which forms, and where is an example" reads a new `book_lemmas` table written at ingest time. The sequence is expand (add the new storage, dual-write, backfill), swap (readers move over), then contract (drop `tokens`).

**Tech Stack:** Rails 8.0, PostgreSQL (JSONB), Minitest, Capybara/Selenium system tests, Python 3 + spaCy for ingest.

---

## Measured baseline

Taken on the development database on 2026-08-23, with three ingested books (463,045 token rows):

| Measurement | Value |
| --- | --- |
| `tokens` total size | 96 MB (62 MB heap + 34 MB indexes) |
| One novel's share | 32.7 MB for 158,099 words |
| Same words as one JSONB array per block | 6.7 MB — **4.9x smaller** |
| Page read, 40 blocks, from token rows | 1.2 ms |
| Page read, 40 blocks, from JSONB blobs | 1.2 ms — no regression |
| Word bank `GROUP BY (lemma_id, surface)`, 200 saved words | 240 ms, spilling to temp files |
| `(book_id, lemma_id)` rollup rows for one novel | 12,213 versus 158,099 token rows |

Re-run the first three after Task 7 to confirm the win.

## Design decisions

**Word entry shape.** One JSON object per word inside `blocks.words`. Keys are single letters because they repeat 158,000 times in a novel, and absent values are omitted rather than stored as null:

```json
{"p": 1, "s": 5, "e": 9, "w": "dijo", "n": 0, "l": 42, "x": "VERB", "m": {"Tense": "Past"}}
```

`p` position within the block, `s`/`e` character offsets into `blocks.text`, `w` surface form, `n` the position of the sentence this word belongs to within the block, `l` lemma id, `x` part of speech, `m` morphology.

**Why `n` and not a sentence id.** Sentences stay in their own table (the translator, the gloss cache key, and `reviews.sentence_id` all need them), but storing a bigint sentence id per word costs more than storing its position within the block, and positions survive a re-ingest of the same text.

**Lemma text.** Not denormalised into the blob. The reader resolves every lemma on the page in one `Lemma.where(id: ...)` query and hands the map to the renderer; a single word card looks its own lemma up lazily.

**What replaces the aggregates.** `book_lemmas` holds one row per `(book_id, lemma_id)` with the occurrence count, a `{surface => count}` map, and one sample occurrence for the quiz to use as an example sentence.

## Behaviour changes to accept

- The quiz's example sentence for a word with no saved source becomes the rollup's sample occurrence in a randomly chosen book the reader owns, instead of a uniformly random occurrence across all their books. Cheap, deterministic per book, and indistinguishable in practice.
- `encountered_forms` counts come from the rollup, so they are exact per book but capped at the surfaces seen at ingest time. Same numbers, different source.
- Word DOM ids change from `w_token_1234` to `w_token_12_3`. Nothing persists these; bookmarks compute them on demand.

## File map

**Created**
- `db/migrate/20260823010000_add_words_to_blocks.rb` — column plus one-time backfill from `tokens`
- `db/migrate/20260823020000_create_book_lemmas.rb` — rollup table plus backfill
- `db/migrate/20260823030000_repoint_bookmarks_and_vocab_at_blocks.rb` — `(block_id, word_position)` pointers plus backfill
- `db/migrate/20260823040000_drop_tokens.rb` — the contract step
- `app/models/book_lemma.rb` — rollup row
- `test/models/block_test.rb` — word array shape and offsets
- `test/models/vocab_entry_test.rb` — occurrence counts and forms off the rollup
- `test/models/token_test.rb` — value object identity, sentence resolution, grammar

**Modified**
- `app/models/token.rb` — ActiveRecord model becomes a value object
- `app/models/block.rb` — `tokens` / `token_at` / `lemma_ids` read from `words`
- `app/models/book.rb`, `app/models/sentence.rb` — drop the `tokens` associations, purge the rollup
- `app/models/bookmark.rb`, `app/models/vocab_entry.rb` — point at `(block, word_position)`
- `app/services/book_ingestor.rb` — write `words` and the rollup, stop writing token rows
- `app/presenters/block_renderer.rb` — take lemma texts and bookmarked positions
- `app/controllers/books_controller.rb`, `tokens_controller.rb`, `bookmarks_controller.rb`, `words_controller.rb`, `quizzes_controller.rb`
- `app/views/books/read.html.erb`, `app/views/books/_block.html.erb`, `app/views/bookmarks/index.html.erb`
- `test/test_helper.rb` and the four tests that build token rows directly

---

### Task 1: Baseline commit

This repository has no commits at all — `git log` is empty and every file is untracked. A refactor that rewrites the storage of every word needs a revert point before it starts.

**Files:**
- Modify: none (commit only)

- [ ] **Step 1: Confirm nothing is committed yet**

Run: `git log --oneline -1`
Expected: `fatal: your current branch 'main' does not have any commits yet`

- [ ] **Step 2: Confirm the suite is green before touching anything**

Run: `bin/rails test && bin/rails test:system`
Expected: all tests pass, 0 failures, 0 errors. If anything fails here, stop and fix it first — you cannot tell a refactor regression from a pre-existing failure otherwise.

- [ ] **Step 3: Commit the working tree**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Initial commit: Spanish reader with PDF ingest, word bank, and quiz

Rails 8 app that ingests Spanish PDFs through spaCy, renders them word by
word for tap-to-translate lookups, and schedules saved words with FSRS.
EOF
)"
```

- [ ] **Step 4: Verify**

Run: `git log --oneline -1 && git status --short`
Expected: one commit listed, and no output from `git status`.

---

### Task 2: Store each block's words inline

Add `blocks.words`, backfill it from `tokens`, and start writing both. Nothing reads the new column yet except its test, so this task cannot break the reader.

**Files:**
- Create: `db/migrate/20260823010000_add_words_to_blocks.rb`
- Create: `test/models/block_test.rb`
- Modify: `app/services/book_ingestor.rb`
- Modify: `test/test_helper.rb`

- [ ] **Step 1: Write the migration**

Create `db/migrate/20260823010000_add_words_to_blocks.rb`:

```ruby
# Every word of a block, inline. One row per word cost 32 MB a novel and bought
# nothing, because words are only ever read a block at a time.
#
# Keys are single letters because they repeat 158,000 times in a book: p position,
# s/e character offsets into blocks.text, w surface, n the sentence's position
# within the block, l lemma id, x part of speech, m morphology. jsonb_strip_nulls
# keeps absent values out of storage entirely.
class AddWordsToBlocks < ActiveRecord::Migration[8.0]
  def up
    add_column :blocks, :words, :jsonb, default: [], null: false

    execute <<~SQL
      UPDATE blocks
      SET words = source.entries
      FROM (
        SELECT t.block_id,
               jsonb_agg(
                 jsonb_strip_nulls(jsonb_build_object(
                   'p', t.position,
                   's', t.char_start,
                   'e', t.char_end,
                   'w', t.surface,
                   'n', s.position,
                   'l', t.lemma_id,
                   'x', t.pos,
                   'm', NULLIF(t.morph, '{}'::jsonb)
                 ))
                 ORDER BY t.position
               ) AS entries
        FROM tokens t
        JOIN sentences s ON s.id = t.sentence_id
        GROUP BY t.block_id
      ) AS source
      WHERE blocks.id = source.block_id
    SQL
  end

  def down
    remove_column :blocks, :words
  end
end
```

- [ ] **Step 2: Run the migration and check the backfill against the rows it came from**

```bash
bin/rails db:migrate
bin/rails runner '
mismatched = Block.where(<<~SQL).count
  jsonb_array_length(words) <> (SELECT count(*) FROM tokens WHERE tokens.block_id = blocks.id)
SQL
puts "blocks whose word array disagrees with their token rows: #{mismatched}"
'
```

Expected: `blocks whose word array disagrees with their token rows: 0`

- [ ] **Step 3: Have the ingester write the column**

In `app/services/book_ingestor.rb`, add `words: payload["words"]` to the row built in `insert_blocks`:

```ruby
      {
        book_id: book.id,
        book_image_id: image_id_for(payload, images_dir),
        position: payload["position"],
        kind: payload["kind"],
        page_number: payload["page"],
        text: payload["text"],
        words: payload["words"],
        created_at: now,
        updated_at: now
      }
```

Populate it in `persist`, before the blocks are inserted, so both the blocks and the token rows are built from the same array:

```ruby
  def persist(buffer, images_dir)
    return if buffer.empty?

    Book.transaction do
      resolve_lemmas(buffer)
      buffer.each { |payload| payload["words"] = words_for(payload) }

      block_ids = insert_blocks(buffer, images_dir)
      sentence_ids = insert_sentences(buffer, block_ids)
      insert_tokens(buffer, block_ids, sentence_ids)
    end
  end
```

And add the builder as a private method, next to `insert_tokens`:

```ruby
  # The word array the reader will read back. Numbered across the whole block rather
  # than per sentence, because that is the order the renderer walks.
  def words_for(payload)
    position = -1

    Array(payload["sentences"]).flat_map { |sentence|
      sentence["tokens"].map do |token|
        position += 1

        entry = {
          "p" => position,
          "s" => token["start"],
          "e" => token["end"],
          "w" => token["surface"],
          "n" => sentence["position"]
        }

        lemma_id = @lemma_ids[lemma_key(token)]
        entry["l"] = lemma_id if lemma_id
        entry["x"] = token["pos"] if token["pos"].present?
        entry["m"] = token["morph"] if token["morph"].present?
        entry
      end
    }
  end
```

- [ ] **Step 4: Have the test builder write the column too**

In `test/test_helper.rb`, rewrite the body of `build_annotated_book` so it records both forms:

```ruby
  def build_annotated_book(user, title: "Prueba")
    text = "Ella dijo la verdad."
    book = user.books.create!(title: title, status: "ready", page_count: 1, block_count: 1)
    block = book.blocks.create!(position: 0, kind: "paragraph", page_number: 1, text: text)
    sentence = book.sentences.create!(block: block, position: 0, char_start: 0, char_end: text.length, text: text)

    cursor = 0
    words = []

    tokens = WORDS.each_with_index.map do |word, index|
      # Scanned forward from the previous token so a short word like "la" is not
      # matched inside an earlier one ("Ella").
      offset = text.index(word[:surface], cursor)
      cursor = offset + word[:surface].length
      lemma = Lemma.find_or_create_by!(text: word[:lemma], pos: word[:pos], language: "es")

      words << { "p" => index, "s" => offset, "e" => cursor, "w" => word[:surface],
                 "n" => 0, "l" => lemma.id, "x" => word[:pos], "m" => word[:morph] }

      book.tokens.create!(
        block: block,
        sentence: sentence,
        lemma: lemma,
        position: index,
        char_start: offset,
        char_end: offset + word[:surface].length,
        surface: word[:surface],
        pos: word[:pos],
        morph: word[:morph]
      )
    end

    block.update!(words: words)
    book.update!(word_count: tokens.size)
    verb = tokens.find { |token| token.surface == "dijo" }

    { book: book, block: block, sentence: sentence, tokens: tokens, token: verb, lemma: verb.lemma }
  end
```

- [ ] **Step 5: Write the failing test**

Create `test/models/block_test.rb`:

```ruby
require "test_helper"

class BlockTest < ActiveSupport::TestCase
  setup do
    @fixture = build_annotated_book(users(:one))
    @block = @fixture[:block]
  end

  test "a block carries one word entry per word, in reading order" do
    assert_equal %w[Ella dijo la verdad], @block.words.map { |word| word["w"] }
    assert_equal [ 0, 1, 2, 3 ], @block.words.map { |word| word["p"] }
  end

  test "word offsets point at the characters the block text actually has" do
    @block.words.each do |word|
      assert_equal word["w"], @block.text[word["s"]...word["e"]],
                   "offsets for #{word["w"].inspect} do not line up with the block text"
    end
  end

  test "every word names the sentence it belongs to" do
    positions = @block.sentences.map(&:position)

    @block.words.each do |word|
      assert_includes positions, word["n"]
    end
  end
end
```

- [ ] **Step 6: Run the test**

Run: `bin/rails test test/models/block_test.rb`
Expected: 3 runs, 0 failures. (The builder change in Step 4 is what makes them pass; if `words` comes back empty, `block.update!` is missing.)

- [ ] **Step 7: Run the whole suite, including the real ingest**

Run: `bin/rails test && bin/rails test:system`
Expected: all pass. `test/system/illustrated_book_test.rb` runs the actual Python pipeline over 18 pages of a real PDF, so it is what proves `words_for` produces sane output.

- [ ] **Step 8: Verify a freshly ingested book agrees with itself**

Run: `bin/rails test test/system/illustrated_book_test.rb`
Then: `bin/rails runner 'book = Book.order(:id).last; puts "words inline: #{book.blocks.sum { |b| b.words.size }}, token rows: #{Token.where(book_id: book.id).count}"'`
Expected: the two numbers match.

- [ ] **Step 9: Commit**

```bash
git add db/migrate/20260823010000_add_words_to_blocks.rb db/schema.rb app/services/book_ingestor.rb test/test_helper.rb test/models/block_test.rb
git commit -m "Store each block's words inline as jsonb alongside the token rows"
```

---

### Task 3: Roll up lemma statistics per book

The word bank asks "how often does this lemma appear in my books, in which forms, and show me one place it happens". Today that is a `GROUP BY` over every token row a reader owns — 240 ms and spilling to temp files with only three books. Answer it from a table sized to lemmas instead of words: 12,213 rows per novel instead of 158,099.

**Files:**
- Create: `db/migrate/20260823020000_create_book_lemmas.rb`
- Create: `app/models/book_lemma.rb`
- Modify: `app/models/book.rb`
- Modify: `app/services/book_ingestor.rb`
- Modify: `test/test_helper.rb`

- [ ] **Step 1: Write the migration**

Create `db/migrate/20260823020000_create_book_lemmas.rb`:

```ruby
# One row per lemma per book: how many times it occurs, the surface forms it wears
# and how often each, and one occurrence to quote as an example.
#
# This is the whole reason the words can stop being rows. Everything that used to
# aggregate over tokens reads this instead, and it is proportional to a reader's
# vocabulary rather than to the length of their library.
class CreateBookLemmas < ActiveRecord::Migration[8.0]
  def up
    create_table :book_lemmas do |t|
      t.references :book, null: false, foreign_key: true
      t.references :lemma, null: false, foreign_key: true
      t.integer :count, null: false, default: 0
      t.jsonb :surfaces, null: false, default: {}
      t.bigint :sample_block_id
      t.integer :sample_word_position

      t.timestamps
    end

    add_index :book_lemmas, %i[book_id lemma_id], unique: true
    # The word bank looks up one lemma across the books a reader owns, so lemma_id
    # has to lead: the unique index above cannot serve that.
    add_index :book_lemmas, %i[lemma_id book_id]

    execute <<~SQL
      WITH forms AS (
        SELECT book_id, lemma_id, surface, count(*) AS uses
        FROM tokens
        WHERE lemma_id IS NOT NULL
        GROUP BY book_id, lemma_id, surface
      ), totals AS (
        SELECT book_id,
               lemma_id,
               sum(uses)::int AS total,
               jsonb_object_agg(surface, uses) AS surfaces
        FROM forms
        GROUP BY book_id, lemma_id
      ), samples AS (
        SELECT DISTINCT ON (book_id, lemma_id)
               book_id, lemma_id, block_id, position
        FROM tokens
        WHERE lemma_id IS NOT NULL
        ORDER BY book_id, lemma_id, id
      )
      INSERT INTO book_lemmas
        (book_id, lemma_id, count, surfaces, sample_block_id, sample_word_position,
         created_at, updated_at)
      SELECT totals.book_id, totals.lemma_id, totals.total, totals.surfaces,
             samples.block_id, samples.position, now(), now()
      FROM totals
      JOIN samples ON samples.book_id = totals.book_id
                  AND samples.lemma_id = totals.lemma_id
    SQL
  end

  def down
    drop_table :book_lemmas
  end
end
```

- [ ] **Step 2: Run it and check the rollup against the rows it came from**

```bash
bin/rails db:migrate
bin/rails runner '
disagreeing = BookLemma.pluck(:book_id, :lemma_id, :count).reject { |book_id, lemma_id, count|
  Token.where(book_id: book_id, lemma_id: lemma_id).count == count
}
puts "rollup rows: #{BookLemma.count}, rows disagreeing with the tokens table: #{disagreeing.size}"
'
```

Expected: a five-figure row count, and `rows disagreeing with the tokens table: 0`

- [ ] **Step 3: Add the model**

Create `app/models/book_lemma.rb`:

```ruby
# How one lemma behaves in one book. Written at ingest time, because after the words
# stop being rows there is nothing left to group by.
class BookLemma < ApplicationRecord
  belongs_to :book
  belongs_to :lemma

  scope :for_books, ->(books) { where(book_id: books) }

  # The occurrence held up as an example in the quiz.
  def sample_token
    return nil if sample_block_id.blank?

    Block.find_by(id: sample_block_id)&.tokens&.find_by(position: sample_word_position)
  end

  # Surface forms across several books of the same reader, merged and ranked.
  def self.merged_surfaces(rows, limit: 12)
    rows.pluck(:surfaces)
        .each_with_object(Hash.new(0)) { |surfaces, totals|
          surfaces.each { |surface, uses| totals[surface] += uses }
        }
        .sort_by { |_, uses| -uses }
        .first(limit)
        .to_h
  end
end
```

Note `sample_token` uses the ActiveRecord `tokens` association here and is rewritten in Task 6 to `block.token_at(sample_word_position)`. It exists now so Task 4 has something to call.

- [ ] **Step 4: Associate and purge it**

In `app/models/book.rb`, add the association below `has_many :tokens`:

```ruby
  has_many :book_lemmas
```

And delete the rollup in `purge_content!`, which runs both on re-ingest and on book deletion:

```ruby
  def purge_content!
    BookLemma.where(book_id: id).delete_all
    Token.where(book_id: id).delete_all
    Sentence.where(book_id: id).delete_all
    Block.where(book_id: id).delete_all
  end
```

- [ ] **Step 5: Have the ingester maintain it**

In `app/services/book_ingestor.rb`, add the accumulator to `initialize`:

```ruby
  def initialize(book)
    @book = book
    @lemma_ids = {}
    @image_ids = {}
    @lemma_stats = {}
    @block_position = 0
    @word_count = 0
  end
```

Accumulate inside `persist`, where the block ids are already in hand:

```ruby
  def persist(buffer, images_dir)
    return if buffer.empty?

    Book.transaction do
      resolve_lemmas(buffer)
      buffer.each { |payload| payload["words"] = words_for(payload) }

      block_ids = insert_blocks(buffer, images_dir)
      sentence_ids = insert_sentences(buffer, block_ids)
      insert_tokens(buffer, block_ids, sentence_ids)
      accumulate_lemma_stats(buffer, block_ids)
    end
  end
```

Add both new private methods next to `words_for`:

```ruby
  # Counted while the words are in hand. Only a few thousand lemmas make up a novel,
  # so this stays small enough to hold for the length of an ingest.
  def accumulate_lemma_stats(buffer, block_ids)
    buffer.each do |payload|
      block_id = block_ids.fetch(payload["position"])

      payload["words"].each do |word|
        lemma_id = word["l"]
        next if lemma_id.blank?

        stat = (@lemma_stats[lemma_id] ||= {
          count: 0,
          surfaces: Hash.new(0),
          sample_block_id: block_id,
          sample_word_position: word["p"]
        })

        stat[:count] += 1
        stat[:surfaces][word["w"]] += 1
      end
    end
  end

  def write_lemma_stats
    return if @lemma_stats.empty?

    now = Time.current
    rows = @lemma_stats.map { |lemma_id, stat|
      {
        book_id: book.id,
        lemma_id: lemma_id,
        count: stat[:count],
        surfaces: stat[:surfaces],
        sample_block_id: stat[:sample_block_id],
        sample_word_position: stat[:sample_word_position],
        created_at: now,
        updated_at: now
      }
    }

    rows.each_slice(1000) { |slice| BookLemma.insert_all(slice, unique_by: %i[book_id lemma_id]) }
  end
```

And write them once the stream is finished, in `call`, before the book is marked ready:

```ruby
      book.file.open do |pdf|
        stream(pdf.path, images_dir)
      end
    end

    write_lemma_stats

    book.update!(
      status: "ready",
      ingested_at: Time.current,
      block_count: block_position,
      word_count: word_count
    )
```

- [ ] **Step 6: Have the test builder write it**

In `test/test_helper.rb`, inside `build_annotated_book`, replace the line `book.update!(word_count: tokens.size)` with:

```ruby
    tokens.group_by(&:lemma_id).each do |lemma_id, group|
      BookLemma.create!(book: book, lemma_id: lemma_id, count: group.size,
                        surfaces: group.each_with_object(Hash.new(0)) { |token, totals| totals[token.surface] += 1 },
                        sample_block_id: block.id, sample_word_position: group.first.position)
    end

    book.update!(word_count: tokens.size)
```

- [ ] **Step 7: Run the suite**

Run: `bin/rails test && bin/rails test:system`
Expected: all pass. Nothing reads `book_lemmas` yet, so a failure here means the ingester or the builder broke.

- [ ] **Step 8: Verify a freshly ingested book gets a rollup**

```bash
bin/rails test test/system/illustrated_book_test.rb
bin/rails runner '
book = Book.order(:id).last
rows = BookLemma.where(book_id: book.id)
puts "lemmas: #{rows.count}, counted occurrences: #{rows.sum(:count)}, token rows: #{Token.where(book_id: book.id).where.not(lemma_id: nil).count}"
'
```

Expected: counted occurrences equals the token row count, and the lemma count is far smaller than both.

- [ ] **Step 9: Commit**

```bash
git add db/migrate/20260823020000_create_book_lemmas.rb db/schema.rb app/models/book_lemma.rb app/models/book.rb app/services/book_ingestor.rb test/test_helper.rb
git commit -m "Roll up per-book lemma counts, surface forms, and a sample occurrence"
```

---

### Task 4: Read the word bank and quiz off the rollup

Swap the four aggregate queries that scan `tokens` for reads of `book_lemmas`. This is the task that removes the 240 ms page.

**Files:**
- Modify: `app/models/vocab_entry.rb:34-46`
- Modify: `app/controllers/words_controller.rb:67-89`
- Modify: `app/controllers/quizzes_controller.rb:55-70`
- Create: `test/models/vocab_entry_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/models/vocab_entry_test.rb`:

```ruby
require "test_helper"

class VocabEntryTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @fixture = build_annotated_book(@user)
    @entry = @user.vocab_entries.create!(lemma: @fixture[:lemma], status: "learning")
  end

  test "occurrence count covers every book the reader owns" do
    assert_equal 1, @entry.occurrence_count

    build_annotated_book(@user, title: "Segundo")

    assert_equal 2, @entry.occurrence_count
  end

  test "occurrence count ignores books belonging to someone else" do
    build_annotated_book(users(:two), title: "Ajeno")

    assert_equal 1, @entry.occurrence_count
  end

  test "encountered forms merge the surfaces seen in each book" do
    build_annotated_book(@user, title: "Segundo")

    assert_equal({ "dijo" => 2 }, @entry.encountered_forms)
  end

  test "a word the reader has no book for has no occurrences" do
    entry = @user.vocab_entries.create!(
      lemma: Lemma.find_or_create_by!(text: "inexistente", pos: "NOUN", language: "es"),
      status: "learning"
    )

    assert_equal 0, entry.occurrence_count
    assert_empty entry.encountered_forms
  end
end
```

- [ ] **Step 2: Run it to watch it fail**

Run: `bin/rails test test/models/vocab_entry_test.rb`
Expected: FAIL. The counts come from `tokens` today, so "occurrence count covers every book the reader owns" passes by accident while `encountered_forms` returns `{"dijo" => 1}` per book rather than a merged map — read the failure before moving on, because it tells you the current shape of the return value.

- [ ] **Step 3: Move the entry's own aggregates onto the rollup**

In `app/models/vocab_entry.rb`, replace `encountered_forms` and `occurrence_count`:

```ruby
  # Distinct surface forms of this word the reader has actually met in their books.
  def encountered_forms(limit: 12)
    BookLemma.merged_surfaces(rollup_rows, limit: limit)
  end

  def occurrence_count
    rollup_rows.sum(:count)
  end

  private

  def rollup_rows
    BookLemma.where(lemma_id: lemma_id).for_books(user.books.select(:id))
  end
```

- [ ] **Step 4: Move the word bank's page-wide aggregates too**

In `app/controllers/words_controller.rb`, replace `occurrence_counts` and `encountered_forms`:

```ruby
  # One grouped read of the rollup for the whole page rather than a count per row.
  def occurrence_counts(entries)
    rollup_for(entries).group(:lemma_id).sum(:count)
  end

  # The distinct surface forms this reader has actually met, per lemma. A word can
  # come from more than one book, so the per-book maps are merged.
  def encountered_forms(entries)
    rollup_for(entries).pluck(:lemma_id, :surfaces)
                       .group_by(&:first)
                       .transform_values { |rows|
                         rows.map(&:last)
                             .each_with_object(Hash.new(0)) { |surfaces, totals|
                               surfaces.each { |surface, uses| totals[surface] += uses }
                             }
                             .sort_by { |_, uses| -uses }
                             .first(8)
                       }
  end

  def rollup_for(entries)
    lemma_ids = entries.map(&:lemma_id)
    return BookLemma.none if lemma_ids.empty?

    BookLemma.where(lemma_id: lemma_ids).for_books(current_user.books.select(:id))
  end
```

- [ ] **Step 5: Point the quiz's example sentence at the rollup**

In `app/controllers/quizzes_controller.rb`, replace `random_token`:

```ruby
  # No saved source: quote the sample occurrence the rollup recorded, from one of the
  # reader's books at random. Cheaper than sampling every occurrence, and the reader
  # cannot tell the difference.
  def random_token(entry)
    BookLemma.where(lemma_id: entry.lemma_id)
             .for_books(current_user.books.select(:id))
             .order(Arel.sql("RANDOM()"))
             .first
             &.sample_token
  end
```

- [ ] **Step 6: Run the tests**

Run: `bin/rails test test/models/vocab_entry_test.rb test/integration/word_bank_flow_test.rb test/integration/quiz_flow_test.rb`
Expected: all pass.

- [ ] **Step 7: Run the whole suite**

Run: `bin/rails test && bin/rails test:system`
Expected: all pass.

- [ ] **Step 8: Confirm the slow query is gone**

```bash
bin/rails runner '
user = Book.first.user
entries = user.vocab_entries.for_listing.to_a
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
rows = BookLemma.where(lemma_id: entries.map(&:lemma_id)).for_books(user.books.select(:id)).pluck(:lemma_id, :count, :surfaces)
puts "#{entries.size} saved words, #{rows.size} rollup rows, #{((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round(1)} ms"
'
```

Expected: single-digit milliseconds. Compare against the 240 ms in the baseline table above.

- [ ] **Step 9: Commit**

```bash
git add app/models/vocab_entry.rb app/controllers/words_controller.rb app/controllers/quizzes_controller.rb test/models/vocab_entry_test.rb
git commit -m "Serve word bank counts and quiz examples from the lemma rollup"
```

---

### Task 5: Point bookmarks and word-bank provenance at `(block, word_position)`

Two tables hold a foreign key to `tokens.id`. Both are really pointing at "this word, in this block", so store that instead. Done before the swap so the pointers never dangle.

**Files:**
- Create: `db/migrate/20260823030000_repoint_bookmarks_and_vocab_at_blocks.rb`
- Modify: `app/models/bookmark.rb`
- Modify: `app/models/vocab_entry.rb:1-20`
- Modify: `app/controllers/bookmarks_controller.rb`
- Modify: `app/controllers/words_controller.rb:22-27`
- Modify: `app/views/bookmarks/index.html.erb:22-27`
- Modify: `test/integration/bookmark_flow_test.rb:61-67`
- Modify: `test/integration/word_bank_flow_test.rb:18`

- [ ] **Step 1: Write the migration**

Create `db/migrate/20260823030000_repoint_bookmarks_and_vocab_at_blocks.rb`:

```ruby
# A bookmark and a saved word both point at one word in one block. That was a token
# id; now it is the block plus the word's position inside it, which is what survives
# the tokens table going away.
class RepointBookmarksAndVocabAtBlocks < ActiveRecord::Migration[8.0]
  def up
    add_column :bookmarks, :block_id, :bigint
    add_column :bookmarks, :word_position, :integer
    add_column :vocab_entries, :source_block_id, :bigint
    add_column :vocab_entries, :source_word_position, :integer

    execute <<~SQL
      UPDATE bookmarks
      SET block_id = tokens.block_id, word_position = tokens.position
      FROM tokens WHERE tokens.id = bookmarks.token_id
    SQL

    execute <<~SQL
      UPDATE vocab_entries
      SET source_block_id = tokens.block_id, source_word_position = tokens.position
      FROM tokens WHERE tokens.id = vocab_entries.source_token_id
    SQL

    # Any bookmark whose token vanished has nothing left to point at.
    execute "DELETE FROM bookmarks WHERE block_id IS NULL"

    change_column_null :bookmarks, :block_id, false
    change_column_null :bookmarks, :word_position, false

    add_index :bookmarks, %i[user_id block_id word_position], unique: true
    add_index :bookmarks, :block_id
    add_index :vocab_entries, :source_block_id

    # Re-ingesting a book replaces its blocks, and every offset a bookmark holds
    # goes with them; provenance on a saved word is nice to have, so it nullifies.
    add_foreign_key :bookmarks, :blocks, on_delete: :cascade
    add_foreign_key :vocab_entries, :blocks, column: :source_block_id, on_delete: :nullify

    remove_column :bookmarks, :token_id
    remove_column :vocab_entries, :source_token_id
  end

  def down
    add_reference :bookmarks, :token, null: true, foreign_key: { on_delete: :cascade }
    add_reference :vocab_entries, :source_token, null: true

    execute <<~SQL
      UPDATE bookmarks
      SET token_id = tokens.id
      FROM tokens
      WHERE tokens.block_id = bookmarks.block_id
        AND tokens.position = bookmarks.word_position
    SQL

    execute <<~SQL
      UPDATE vocab_entries
      SET source_token_id = tokens.id
      FROM tokens
      WHERE tokens.block_id = vocab_entries.source_block_id
        AND tokens.position = vocab_entries.source_word_position
    SQL

    remove_column :bookmarks, :block_id
    remove_column :bookmarks, :word_position
    remove_column :vocab_entries, :source_block_id
    remove_column :vocab_entries, :source_word_position
  end
end
```

- [ ] **Step 2: Run it and check every bookmark still resolves to the word it marked**

```bash
bin/rails db:migrate
bin/rails runner '
resolved = Bookmark.all.count { |mark| Token.exists?(block_id: mark.block_id, position: mark.word_position) }
puts "bookmarks: #{Bookmark.count}, still resolving to a word: #{resolved}"
puts "saved words with provenance: #{VocabEntry.where.not(source_block_id: nil).count}"
'
```

Expected: bookmarks and resolving counts are equal.

- [ ] **Step 3: Rewrite the bookmark model**

Replace `app/models/bookmark.rb` entirely:

```ruby
# A place in a book, marked on one word.
#
# Stored as the block plus the word's position inside it, with the block's position
# copied alongside so the reader can ask "which bookmarks fall on this page" with one
# indexed range query instead of a list of every word on screen.
class Bookmark < ApplicationRecord
  belongs_to :user
  belongs_to :book
  belongs_to :block

  scope :in_reading_order, -> { order(:block_position, :word_position) }

  before_validation :copy_position_from_block

  validates :word_position, presence: true, uniqueness: { scope: %i[user_id block_id] }

  # Marking is done by handing over a word; the block and offset are what get stored.
  def token=(token)
    self.block = token.block
    self.word_position = token.position
  end

  def token
    block&.tokens&.find_by(position: word_position)
  end

  def page
    book.page_for_block_position(block_position)
  end

  def anchor
    word = token
    word && ActionView::RecordIdentifier.dom_id(word, :w)
  end

  private

  def copy_position_from_block
    return if block.blank?

    self.book_id ||= block.book_id
    self.block_position ||= block.position
  end
end
```

`token` goes through the ActiveRecord association for now and becomes `block&.token_at(word_position)` in Task 6, at which point it stops being a query.

- [ ] **Step 4: Repoint the vocabulary entry**

In `app/models/vocab_entry.rb`, replace the `source_token` association and the listing scope:

```ruby
  belongs_to :source_book, class_name: "Book", optional: true
  belongs_to :source_block, class_name: "Block", optional: true
```

```ruby
  # Everything the word bank list needs, so no row triggers its own queries.
  scope :for_listing, -> { includes(:lemma, :source_book, :source_block) }
```

And add the reader, next to `encountered_forms`:

```ruby
  # The word this entry was saved from, if its book has not been re-ingested since.
  def source_token
    source_block&.tokens&.find_by(position: source_word_position)
  end
```

- [ ] **Step 5: Update the two controllers that write these**

In `app/controllers/bookmarks_controller.rb`, `create` and `render_button` address the pair:

```ruby
  def create
    token = find_token(params[:token_id])
    @bookmark = current_user.bookmarks.find_or_create_by!(
      block_id: token.block_id,
      word_position: token.position
    )

    render_button(token)
  end
```

```ruby
  def render_button(token)
    render partial: "bookmarks/button",
           locals: { token: token,
                     bookmark: current_user.bookmarks.find_by(block_id: token.block_id,
                                                              word_position: token.position),
                     total: current_user.bookmarks.where(book_id: token.book_id).count }
  end
```

And `index` loads blocks rather than tokens:

```ruby
  def index
    @book = current_user.books.find(params[:book_id])
    @bookmarks = current_user.bookmarks
                             .where(book: @book)
                             .in_reading_order
                             .includes(block: :sentences)
  end
```

In `app/controllers/words_controller.rb`, `add` records the pair:

```ruby
    @entry = current_user.vocab_entries.find_or_create_by!(lemma_id: @token.lemma_id) do |entry|
      entry.status = "learning"
      entry.source_book_id = @token.book_id
      entry.source_block_id = @token.block_id
      entry.source_word_position = @token.position
      entry.gloss = suggested_gloss(@token)
    end
```

- [ ] **Step 6: Update the bookmarks list view**

In `app/views/bookmarks/index.html.erb`, the row reads the block directly instead of going through the word:

```erb
          <div class="bookmark-row__main">
            <div class="bookmark-row__context"><%= highlight_target(bookmark.token) %></div>
            <div class="bookmark-row__meta">
              Page <%= bookmark.page %>
              <% if bookmark.block.page_number %>
                &middot; book page <%= bookmark.block.page_number %>
              <% end %>
              &middot; marked <%= time_ago_in_words(bookmark.created_at) %> ago
            </div>
          </div>
```

- [ ] **Step 7: Update the two tests that assert on token ids**

In `test/integration/bookmark_flow_test.rb`, the reading-order test compares blocks, since that is what ordering now means:

```ruby
  test "bookmarks are listed in reading order rather than when they were placed" do
    late_token = append_block_with_token(@book, position: 1, text: "Vino después.")

    @user.bookmarks.create!(token: late_token)
    @user.bookmarks.create!(token: @token)

    assert_equal [ @token.block.id, late_token.block.id ],
                 @user.bookmarks.in_reading_order.map(&:block_id)
  end
```

In `test/integration/word_bank_flow_test.rb`, line 18 asserts the pair:

```ruby
    assert_equal [ @fixture[:token].block_id, @fixture[:token].position ],
                 [ entry.source_block_id, entry.source_word_position ]
```

- [ ] **Step 8: Run the affected tests**

Run: `bin/rails test test/integration/bookmark_flow_test.rb test/integration/word_bank_flow_test.rb test/system/bookmark_test.rb`
Expected: all pass.

- [ ] **Step 9: Run the whole suite**

Run: `bin/rails test && bin/rails test:system`
Expected: all pass.

- [ ] **Step 10: Commit**

```bash
git add db/migrate/20260823030000_repoint_bookmarks_and_vocab_at_blocks.rb db/schema.rb app/models/bookmark.rb app/models/vocab_entry.rb app/controllers/bookmarks_controller.rb app/controllers/words_controller.rb app/views/bookmarks/index.html.erb test/integration/bookmark_flow_test.rb test/integration/word_bank_flow_test.rb
git commit -m "Address bookmarks and saved-word provenance by block and word position"
```

---

### Task 6: Make `Token` a value object

The one commit that cannot be split, because the class name can only mean one thing at a time. Everything that reads a word switches to `blocks.words`, and the ingester stops writing token rows. The table stays behind, unread, until Task 7.

**Files:**
- Modify: `app/models/token.rb` (rewritten)
- Modify: `app/models/block.rb`, `app/models/sentence.rb`, `app/models/book.rb`
- Modify: `app/models/bookmark.rb`, `app/models/vocab_entry.rb`, `app/models/book_lemma.rb`
- Modify: `app/presenters/block_renderer.rb`
- Modify: `app/controllers/application_controller.rb`, `books_controller.rb`, `tokens_controller.rb`, `bookmarks_controller.rb`, `words_controller.rb`, `quizzes_controller.rb`
- Modify: `app/views/books/read.html.erb`, `app/views/books/_block.html.erb`
- Modify: `app/services/book_ingestor.rb`
- Create: `test/models/token_test.rb`
- Modify: `test/test_helper.rb` and four tests that build token rows

- [ ] **Step 1: Write the failing test for the value object**

Create `test/models/token_test.rb`:

```ruby
require "test_helper"

class TokenTest < ActiveSupport::TestCase
  setup do
    @fixture = build_annotated_book(users(:one))
    @block = @fixture[:block]
    @token = @fixture[:token]
  end

  test "a word is identified by its block and its position in it" do
    assert_equal "#{@block.id}-1", @token.id
    assert_equal "#{@block.id}-1", @token.to_param
    assert_equal [ @block.id, 1 ], @token.to_key
  end

  test "dom ids stay addressable, which is what makes a bookmark a link" do
    assert_equal "w_token_#{@block.id}_1", ActionView::RecordIdentifier.dom_id(@token, :w)
  end

  test "a word can be looked up again from its id" do
    found = Token.locate(Block.where(book_id: @fixture[:book].id), @token.id)

    assert_equal @token, found
    assert_equal "dijo", found.surface
  end

  test "looking up a malformed or missing word raises rather than returning nil" do
    scope = Block.where(book_id: @fixture[:book].id)

    assert_raises(ActiveRecord::RecordNotFound) { Token.locate(scope, "nonsense") }
    assert_raises(ActiveRecord::RecordNotFound) { Token.locate(scope, "#{@block.id}-99") }
  end

  test "a word finds the sentence it sits in" do
    assert_equal @fixture[:sentence], @token.sentence
  end

  test "grammar comes from the morphology recorded at ingest time" do
    assert_equal "verdad", @block.token_at(3).surface
    assert_match(/past/i, @token.grammar_summary)
    assert @token.inflected?, "dijo should read as inflected from decir"
  end

  test "the block exposes its words in reading order" do
    assert_equal %w[Ella dijo la verdad], @block.tokens.map(&:surface)
    assert_equal [ 0, 1, 2, 3 ], @block.tokens.map(&:position)
    assert_nil @block.token_at(99)
  end
end
```

- [ ] **Step 2: Run it to watch it fail**

Run: `bin/rails test test/models/token_test.rb`
Expected: FAIL — `Token.locate` is undefined and `Token#id` returns an integer.

- [ ] **Step 3: Rewrite the token as a value object**

Replace `app/models/token.rb` entirely:

```ruby
# One word occurrence in a book: a value read out of blocks.words, not a table row.
#
# A row per word cost 32 MB a novel and bought nothing the reader needed, because
# words are only ever fetched a block at a time. Anything that wants to count
# occurrences across a library reads book_lemmas instead.
#
# Identity is the pair (block, position): "<block_id>-<position>" in a URL and
# token_<block_id>_<position> as a DOM id, which is what keeps every word
# addressable and a bookmark a link you can follow.
class Token
  include ActiveModel::Conversion
  extend ActiveModel::Naming

  attr_reader :block, :position, :char_start, :char_end, :surface, :pos, :morph,
              :sentence_position, :lemma_id
  attr_writer :lemma_text

  def self.from_data(block, data)
    new(
      block: block,
      position: data["p"],
      char_start: data["s"],
      char_end: data["e"],
      surface: data["w"],
      sentence_position: data["n"].to_i,
      lemma_id: data["l"],
      pos: data["x"],
      morph: data["m"] || {}
    )
  end

  # Resolves "<block_id>-<position>" inside a scope of blocks the reader may see, so
  # an id from someone else's book is a 404 rather than a leak.
  def self.locate(blocks, id)
    block_id, position = id.to_s.split("-", 2)
    raise ActiveRecord::RecordNotFound, "malformed word id #{id.inspect}" if position.blank?

    block = blocks.find(block_id)
    block.token_at(position.to_i) ||
      raise(ActiveRecord::RecordNotFound, "block #{block_id} has no word at position #{position}")
  end

  def initialize(block:, position:, char_start:, char_end:, surface:,
                 sentence_position: 0, lemma_id: nil, pos: nil, morph: {})
    @block = block
    @position = position
    @char_start = char_start
    @char_end = char_end
    @surface = surface
    @sentence_position = sentence_position
    @lemma_id = lemma_id
    @pos = pos
    @morph = morph
  end

  def id
    "#{block.id}-#{position}"
  end
  alias to_param id

  # A two part key, so dom_id renders token_<block_id>_<position>.
  def to_key
    [ block.id, position ]
  end

  def persisted?
    true
  end

  def ==(other)
    other.is_a?(Token) && other.to_key == to_key
  end
  alias eql? ==

  def hash
    to_key.hash
  end

  def block_id
    block.id
  end

  def book_id
    block.book_id
  end

  # Sentences are still rows: the translator prompts with them, the gloss cache is
  # keyed on them, and a review records the one it quizzed.
  def sentence
    block.sentences.detect { |candidate| candidate.position == sentence_position }
  end
  alias context_sentence sentence

  # Set in bulk by the reader, which resolves every lemma on the page at once. Falls
  # back to its own lookup for a single word card.
  def lemma_text
    return @lemma_text if defined?(@lemma_text)

    @lemma_text = lemma_id.present? ? Lemma.where(id: lemma_id).pick(:text) : nil
  end

  # Everything a hover tooltip shows, derived from data computed at ingest time.
  # No network call and no model inference happens here.
  def morphology
    @morphology ||= Morphology.new(pos: pos, features: morph)
  end

  def grammar_summary
    morphology.summary
  end

  def inflected?
    lemma_text.present? && lemma_text.casecmp(surface).to_i != 0
  end
end
```

- [ ] **Step 4: Build the words in the block**

In `app/models/block.rb`, drop `has_many :tokens` and add the readers:

```ruby
class Block < ApplicationRecord
  KINDS = %w[paragraph heading image].freeze

  belongs_to :book
  belongs_to :book_image, optional: true

  has_many :sentences, -> { order(:position) }, dependent: :delete_all

  validates :kind, inclusion: { in: KINDS }

  scope :in_order, -> { order(:position) }

  KINDS.each do |value|
    define_method(:"#{value}?") { kind == value }
  end

  # The words of this block. `words` is the raw jsonb column and nothing outside this
  # model should read it directly.
  def tokens
    @tokens ||= Array(words).map { |data| Token.from_data(self, data) }
  end

  def token_at(position)
    tokens.detect { |token| token.position == position }
  end

  def lemma_ids
    tokens.filter_map(&:lemma_id).uniq
  end
end
```

- [ ] **Step 5: Drop the remaining associations to the table**

In `app/models/sentence.rb`, remove the line `has_many :tokens, -> { order(:position) }, dependent: :nullify`.

In `app/models/book.rb`, remove `has_many :tokens` and take the table out of the purge:

```ruby
  # Deleted innermost first: sentences reference blocks. Used both when removing a
  # book and when re-ingesting one. Bookmarks go with the blocks by cascade, since
  # re-ingesting changes every offset they point at.
  def purge_content!
    BookLemma.where(book_id: id).delete_all
    Sentence.where(book_id: id).delete_all
    Block.where(book_id: id).delete_all
  end
```

- [ ] **Step 6: Resolve words from blocks in the three models that hold pointers**

In `app/models/bookmark.rb`:

```ruby
  def token
    block&.token_at(word_position)
  end
```

In `app/models/vocab_entry.rb`:

```ruby
  def source_token
    source_block&.token_at(source_word_position)
  end
```

In `app/models/book_lemma.rb`:

```ruby
  def sample_token
    return nil if sample_block_id.blank?

    Block.find_by(id: sample_block_id)&.token_at(sample_word_position)
  end
```

- [ ] **Step 7: Give the renderer the page's lemma texts and bookmarked positions**

In `app/presenters/block_renderer.rb`, replace the constructor and `word_span`:

```ruby
  # Lemma ids the reader has saved, mapped to their study status, so a saved word
  # highlights in every one of its conjugations. Lemma texts come in resolved for the
  # whole page, because the blob stores ids rather than repeating the text per word.
  #
  # Bookmarked positions are separate from that: a bookmark marks one occurrence of
  # one word, because it stands for a place in the book rather than for vocabulary.
  def initialize(block, lemma_texts: {}, statuses_by_lemma: {}, bookmarked_positions: [])
    @block = block
    @tokens = block.tokens
    @lemma_texts = lemma_texts
    @statuses_by_lemma = statuses_by_lemma
    @bookmarked_positions = bookmarked_positions.to_set
  end
```

```ruby
  attr_reader :block, :tokens, :lemma_texts, :statuses_by_lemma, :bookmarked_positions
```

```ruby
  def word_span(token)
    surface = text[token.char_start...token.char_end]
    status = statuses_by_lemma[token.lemma_id]

    classes = [ "w" ]
    classes << "w--#{status}" if status
    classes << "w--bookmarked" if bookmarked_positions.include?(token.position)

    attributes = {
      # Every word is addressable, which is what makes a bookmark a link you can
      # follow rather than just a page number.
      id: dom_id(token, :w),
      class: classes.join(" "),
      "data-token-id" => token.id,
      "data-lemma-id" => token.lemma_id,
      "data-lemma" => lemma_texts[token.lemma_id],
      "data-grammar" => token.grammar_summary
    }

    tag = +"<span"
    attributes.each { |name, value| tag << %( #{name}="#{escape(value)}") if value.present? }
    tag << ">" << escape(surface) << "</span>"
    tag
  end
```

- [ ] **Step 8: Look words up in one place**

In `app/controllers/application_controller.rb`, add a shared finder under the existing `private` section, below `current_user`:

```ruby
  private

  def current_user
    Current.user
  end

  # Words are addressed as "<block_id>-<position>", and only inside books the signed
  # in reader owns.
  def find_token(id)
    Token.locate(Block.where(book_id: current_user.books.select(:id)), id)
  end
```

Then delete the private `find_token` from `app/controllers/words_controller.rb` and `app/controllers/bookmarks_controller.rb`, and replace `set_token` in `app/controllers/tokens_controller.rb`:

```ruby
  def set_token
    @token = find_token(params[:id])
  end
```

- [ ] **Step 9: Rebuild the reader page around the blobs**

In `app/controllers/books_controller.rb`, `read` no longer fetches tokens:

```ruby
    @lemma_texts = lemma_texts_for(@blocks)
    @statuses_by_lemma = statuses_by_lemma
    @bookmarked_positions = bookmarked_positions(offset)
    @bookmark_count = current_user.bookmarks.where(book: @book).count
```

Replace the private `tokens_for` and `bookmarked_token_ids` with:

```ruby
  # One query for every lemma on the page. The blob stores lemma ids rather than
  # repeating the text 3,000 times, so this is what turns them back into words.
  def lemma_texts_for(blocks)
    ids = blocks.flat_map(&:lemma_ids).uniq
    return {} if ids.empty?

    Lemma.where(id: ids).pluck(:id, :text).to_h
  end

  # Only the marks that fall on this page, matched on the same block range the page
  # was built from. This is what the denormalised block_position buys: an index hit
  # instead of a list of every word on screen.
  def bookmarked_positions(offset)
    current_user.bookmarks
                .where(book: @book, block_position: offset...(offset + Book::BLOCKS_PER_PAGE))
                .pluck(:block_id, :word_position)
                .group_by(&:first)
                .transform_values { |rows| rows.map(&:last).to_set }
  end
```

In `app/views/books/read.html.erb`, pass the new locals:

```erb
    <% @blocks.each do |block| %>
      <%= render "books/block", block: block,
                                lemma_texts: @lemma_texts,
                                statuses_by_lemma: @statuses_by_lemma,
                                bookmarked_positions: @bookmarked_positions.fetch(block.id, []) %>
    <% end %>
```

In `app/views/books/_block.html.erb`, build the renderer from them:

```erb
<% renderer = BlockRenderer.new(block, lemma_texts: lemma_texts,
                                       statuses_by_lemma: statuses_by_lemma,
                                       bookmarked_positions: bookmarked_positions) %>
```

- [ ] **Step 10: Simplify the quiz example**

In `app/controllers/quizzes_controller.rb`, `example_for` no longer needs to re-read the word to get its lemma text:

```ruby
  # The sentence to quiz in. Prefers the passage where the word was first saved,
  # which is the context the reader actually has a memory of.
  def example_for(entry)
    token = entry.source_token || random_token(entry)
    return nil if token.blank?

    { token: token, sentence: token.sentence }
  end
```

- [ ] **Step 11: Stop writing token rows**

In `app/services/book_ingestor.rb`, `persist` drops the token insert and counts words where they are built:

```ruby
  def persist(buffer, images_dir)
    return if buffer.empty?

    Book.transaction do
      resolve_lemmas(buffer)
      prepare_words(buffer)

      block_ids = insert_blocks(buffer, images_dir)
      insert_sentences(buffer, block_ids)
      accumulate_lemma_stats(buffer, block_ids)
    end
  end

  def prepare_words(buffer)
    buffer.each do |payload|
      payload["words"] = words_for(payload)
      @word_count += payload["words"].size
    end
  end
```

Delete the `insert_tokens` method entirely.

- [ ] **Step 12: Rebuild the test builder**

Replace the `BookBuilder` module in `test/test_helper.rb`:

```ruby
# Builds a small annotated book directly, standing in for the Python pipeline so
# tests do not need spaCy installed.
#
# Note the punctuation: only words get entries, so the final period exercises the
# renderer's handling of the gaps between them.
module BookBuilder
  WORDS = [
    { surface: "Ella", lemma: "ella", pos: "PRON", morph: { "Gender" => "Fem", "Number" => "Sing", "Person" => "3" } },
    { surface: "dijo", lemma: "decir", pos: "VERB", morph: { "Mood" => "Ind", "Number" => "Sing", "Person" => "3", "Tense" => "Past", "VerbForm" => "Fin" } },
    { surface: "la", lemma: "el", pos: "DET", morph: { "Gender" => "Fem", "Number" => "Sing" } },
    { surface: "verdad", lemma: "verdad", pos: "NOUN", morph: { "Gender" => "Fem", "Number" => "Sing" } }
  ].freeze

  def build_annotated_book(user, title: "Prueba")
    book = user.books.create!(title: title, status: "ready", page_count: 1, block_count: 1)
    built = build_block_with_words(book, position: 0, text: "Ella dijo la verdad.", words: WORDS)

    book.update!(word_count: built[:tokens].size)
    verb = built[:tokens].find { |token| token.surface == "dijo" }

    { book: book, block: built[:block], sentence: built[:sentence],
      tokens: built[:tokens], token: verb, lemma: Lemma.find(verb.lemma_id) }
  end

  # One paragraph, its sentence, its inline words, and the lemma rollup they imply.
  # Each word needs a :surface and may carry :lemma, :pos and :morph.
  def build_block_with_words(book, position:, text:, words:, page_number: nil)
    block = book.blocks.create!(position: position, kind: "paragraph",
                                page_number: page_number || position + 1, text: text)
    sentence = book.sentences.create!(block: block, position: 0, char_start: 0,
                                      char_end: text.length, text: text)

    cursor = 0

    entries = words.each_with_index.map do |word, index|
      # Scanned forward from the previous word so a short one like "la" is not
      # matched inside an earlier one ("Ella").
      offset = text.index(word[:surface], cursor)
      raise ArgumentError, "#{word[:surface].inspect} is not in #{text.inspect}" if offset.nil?

      cursor = offset + word[:surface].length

      entry = { "p" => index, "s" => offset, "e" => cursor, "w" => word[:surface], "n" => 0 }
      entry["x"] = word[:pos] if word[:pos]
      entry["m"] = word[:morph] if word[:morph]

      if word[:lemma]
        lemma = Lemma.find_or_create_by!(text: word[:lemma], pos: word[:pos] || "NOUN", language: "es")
        entry["l"] = lemma.id
      end

      entry
    end

    block.update!(words: entries)
    record_lemma_stats(book, block)

    { block: block, sentence: sentence, tokens: block.tokens }
  end

  private

  # The same rollup the ingester writes, so tests exercise the aggregates the word
  # bank actually reads.
  def record_lemma_stats(book, block)
    block.tokens.group_by(&:lemma_id).each do |lemma_id, group|
      next if lemma_id.blank?

      rollup = BookLemma.find_or_initialize_by(book_id: book.id, lemma_id: lemma_id)
      rollup.count += group.size
      rollup.surfaces = group.each_with_object(rollup.surfaces.dup) { |token, totals|
        totals[token.surface] = totals.fetch(token.surface, 0) + 1
      }
      rollup.sample_block_id ||= block.id
      rollup.sample_word_position ||= group.first.position
      rollup.save!
    end
  end
end
```

- [ ] **Step 13: Update the four tests that built token rows**

In `test/integration/bookmark_flow_test.rb`, the helper at the bottom:

```ruby
  # A second paragraph further into the book, so reading order is something other
  # than insertion order.
  def append_block_with_token(book, position:, text:)
    build_block_with_words(book, position: position, text: text,
                           words: [ { surface: "Vino", lemma: "venir", pos: "VERB" } ])[:tokens].first
  end
```

And the Turbo frame header on line 83, which now has to be built the same way the view builds it:

```ruby
    delete bookmark_path(bookmark),
           headers: { "Turbo-Frame" => ActionView::RecordIdentifier.dom_id(@token, :bookmark) }
```

In `test/queries/resume_points_test.rb`, both helpers:

```ruby
  def token_on(page:, offset:)
    position = (page - 1) * Book::BLOCKS_PER_PAGE + offset
    @book.blocks.find_by!(position: position).token_at(0)
  end

  # Six reader pages, one word per block, each block carrying its own page number.
  def build_paged_book(user, title: "Paginado")
    count = Book::BLOCKS_PER_PAGE * 6
    book = user.books.create!(title: title, status: "ready", block_count: count, page_count: count)

    count.times do |index|
      build_block_with_words(book, position: index,
                             text: "Bloque #{index + 1}: ella habló.",
                             words: [ { surface: "ella", lemma: "ella", pos: "PRON" } ])
    end

    book
  end
```

In `test/system/bookmark_test.rb`:

```ruby
  # Three reader pages of prose, so bookmarks have somewhere to point other than the
  # first screen.
  def build_long_book(user)
    count = Book::BLOCKS_PER_PAGE * 3
    book = user.books.create!(title: "Cuentos", status: "ready", block_count: count, page_count: count)

    count.times do |index|
      build_block_with_words(book, position: index,
                             text: "Bloque #{index + 1}: ella dijo la verdad.",
                             words: [ { surface: "ella", lemma: "ella", pos: "PRON" } ])
    end

    book
  end
```

In `test/system/word_card_placement_test.rb`:

```ruby
  # Enough prose to fill more than one screen, so there are words at both ends of the
  # viewport to click.
  def build_wordy_book(user)
    count = 30
    book = user.books.create!(title: "Prosa", status: "ready", block_count: count, page_count: count)

    count.times do |index|
      build_block_with_words(
        book,
        position: index,
        text: "Bloque #{index + 1}: ella dijo la verdad sobre el jardín escondido.",
        words: %w[ella dijo verdad jardín].map { |surface| { surface: surface, lemma: surface, pos: "NOUN" } }
      )
    end

    book
  end
```

In `test/integration/word_bank_flow_test.rb`, line 96 asserts the content is gone by looking at blocks, since there is no token table to count:

```ruby
    assert_equal 0, Block.where(book_id: @fixture[:book].id).count
```

- [ ] **Step 14: Run the new unit tests**

Run: `bin/rails test test/models/token_test.rb test/models/block_test.rb test/models/vocab_entry_test.rb`
Expected: all pass.

- [ ] **Step 15: Run everything**

Run: `bin/rails test && bin/rails test:system`
Expected: all pass. `test/system/reader_test.rb` proves a word still opens a card, `bookmark_test.rb` that a mark still lands and is still followable, and `illustrated_book_test.rb` that a real PDF still ingests into readable blocks.

- [ ] **Step 16: Read a real book in the browser**

```bash
bin/rails server
```

Open an already-ingested book, click a word, add it to the bank, bookmark it, reload the page, and follow the bookmark from the bookmarks list. The old token rows are still in the database but nothing reads them, so anything that works here works without them.

- [ ] **Step 17: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Read words out of blocks.words instead of a row per word

Token becomes a value object identified by (block, position). The tokens table
is left in place, unread, so the drop is its own reversible step.
EOF
)"
```

---

### Task 7: Drop the tokens table and measure the result

**Files:**
- Create: `db/migrate/20260823040000_drop_tokens.rb`

- [ ] **Step 1: Prove nothing references the table any more**

Run: `rg -n "\bTokens?\b" app lib db/seeds.rb test --glob '!db/schema.rb' | rg -v "Token\.locate|Token\.from_data|class Token|token_|Tokens?Controller"`
Expected: no hits that read or write the table. Every remaining mention should be the value object, its helpers, or a route/partial name.

- [ ] **Step 2: Record the sizes you are about to change**

```bash
bin/rails runner '
c = ActiveRecord::Base.connection
%w[tokens blocks sentences book_lemmas].each do |table|
  next unless c.table_exists?(table)
  puts format("%-12s %s", table, c.select_value("SELECT pg_size_pretty(pg_total_relation_size(#{c.quote(table)}))"))
end
'
```

Write the numbers down; Step 5 compares against them.

- [ ] **Step 3: Write the migration**

Create `db/migrate/20260823040000_drop_tokens.rb`:

```ruby
# The words moved into blocks.words and their aggregates into book_lemmas, so the
# 150,000 rows a novel used to need are gone.
#
# Irreversible on purpose: down would have to invent primary keys that nothing holds
# a reference to any more. Re-ingesting a book rebuilds everything this held.
class DropTokens < ActiveRecord::Migration[8.0]
  def up
    drop_table :tokens
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "words live in blocks.words now; re-ingest a book to rebuild its words"
  end
end
```

- [ ] **Step 4: Run it and reclaim the space**

```bash
bin/rails db:migrate
bin/rails runner 'ActiveRecord::Base.connection.execute("VACUUM ANALYZE blocks")'
```

- [ ] **Step 5: Measure the win**

```bash
bin/rails runner '
c = ActiveRecord::Base.connection
book = Book.first
total = %w[blocks sentences book_lemmas].sum { |t| c.select_value("SELECT pg_total_relation_size(#{c.quote(t)})").to_i }
puts "content tables now: #{(total / 1024.0 / 1024).round(1)} MB for #{Book.count} books"
plan = c.select_all(%{
  EXPLAIN (ANALYZE) SELECT words FROM blocks
  WHERE book_id = #{book.id} ORDER BY position LIMIT 40
}).rows.flatten
puts plan.grep(/Execution Time/).first
'
```

Expected: the three content tables together come to roughly a fifth of what `tokens` alone used, and a page still reads in single-digit milliseconds. Compare against the baseline table at the top of this plan.

- [ ] **Step 6: Run everything one more time**

Run: `bin/rails test && bin/rails test:system`
Expected: all pass.

- [ ] **Step 7: Re-ingest a book end to end**

```bash
bin/rails runner 'BookIngestor.new(Book.first).call'
bin/rails runner '
book = Book.first
puts "blocks #{book.blocks.count}, words #{book.blocks.sum { |b| b.words.size }}, word_count #{book.word_count}, rollup #{BookLemma.where(book_id: book.id).count}"
'
```

Expected: `words` and `word_count` agree, and the rollup has a five-figure row count. This is the proof that ingest no longer depends on the dropped table.

- [ ] **Step 8: Commit**

```bash
git add db/migrate/20260823040000_drop_tokens.rb db/schema.rb
git commit -m "Drop the tokens table"
```

---

### Task 8: Write down how words are stored

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Document the storage in the README**

Find the section describing the data model and add, in the same voice as its neighbours:

```markdown
### How words are stored

A block keeps its words inline, in a `words` JSONB array, rather than as a row each.
One novel is about 158,000 words: as rows that was 33 MB a book, and as one array per
block it is under 7 MB, with page reads no slower because words are only ever fetched
a block at a time.

Each entry is `{"p": position, "s": start, "e": end, "w": surface, "n": sentence,
"l": lemma_id, "x": pos, "m": morphology}`, with absent values left out. Offsets are
relative to `blocks.text`, so the renderer walks them in order and emits the untouched
gaps in between to reproduce the original punctuation exactly.

`Token` is a value object built from those entries, identified by the pair
`(block, position)` — `"<block_id>-<position>"` in a URL, `token_<block_id>_<position>`
as a DOM id. That is what lets a bookmark or a saved word point back at one exact word.

Counting occurrences across a library cannot be done against blobs, so `book_lemmas`
holds one row per book per lemma with its count, a `{surface => count}` map, and one
sample occurrence for the quiz to quote. It is written at ingest time and is
proportional to a reader's vocabulary rather than to the length of their books.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "Document how a block stores its words"
```

---

## Self-review

Checked after writing, against the design decisions above.

**Coverage.** Every consumer of the old table has a task: the reader page and renderer (6), the word card and translator (6, via `find_token` and `Token#sentence`), bookmarks (5, 6), word-bank provenance (5), occurrence counts and encountered forms (4), the quiz example (4, 6), ingest (2, 3, 6), and the four test builders (6). The two remaining reads of `tokens` after Task 4 are the verification commands in Tasks 2, 3 and 5, which exist precisely to compare old against new and disappear with Task 7.

**Naming consistency.** `Token.from_data` builds, `Token.locate` resolves, `Block#tokens` / `Block#token_at` / `Block#lemma_ids` read, `Bookmark#token` and `VocabEntry#source_token` and `BookLemma#sample_token` all return the value object. `find_token` is the one controller-level finder. The renderer takes `lemma_texts:`, `statuses_by_lemma:` and `bookmarked_positions:` in every place it is constructed (`_block.html.erb`) and passed (`read.html.erb`).

**Ordering.** Tasks 2 through 5 each leave the app green with the old table still authoritative, so any of them can be reverted alone. Task 6 is the only atomic multi-file change, because a class name can mean one thing at a time; it is preceded by a commit that gives it a clean revert point and followed by a suite run plus a manual pass in the browser. Task 7 is the only irreversible step and it comes last.

**Things deliberately not in this plan.** Deduplicating identical PDFs by checksum, caching rendered page HTML, and moving Active Storage off the local disk are all separate wins and separate plans. This one only changes how words are stored.
