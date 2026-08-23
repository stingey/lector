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
    # The word bank looks one lemma up across the books a reader owns, so lemma_id has
    # to lead: the unique index above cannot serve that.
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
