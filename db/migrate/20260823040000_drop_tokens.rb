# The words moved into blocks.words and their aggregates into book_lemmas, so the
# 150,000 rows a novel used to need are gone.
#
# Irreversible on purpose: down would have to invent primary keys that nothing holds a
# reference to any more. Re-ingesting a book rebuilds everything this held.
class DropTokens < ActiveRecord::Migration[8.0]
  def up
    drop_table :tokens
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "words live in blocks.words now; re-ingest a book to rebuild its words"
  end
end
