# Every word of a block, inline. One row per word cost 32 MB a novel and bought
# nothing, because words are only ever read a block at a time.
#
# Keys are single letters because they repeat 158,000 times in a book: p position,
# s/e character offsets into blocks.text, w surface, n the sentence's position within
# the block, l lemma id, x part of speech, m morphology. jsonb_strip_nulls keeps
# absent values out of storage entirely.
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
