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

    # Re-ingesting a book replaces its blocks, and every offset a bookmark holds goes
    # with them; provenance on a saved word is nice to have, so it nullifies.
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
