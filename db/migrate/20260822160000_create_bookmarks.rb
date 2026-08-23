class CreateBookmarks < ActiveRecord::Migration[8.0]
  def change
    create_table :bookmarks do |t|
      t.references :user, null: false, foreign_key: true
      t.references :book, null: false, foreign_key: true

      # A bookmark is a position, so it cascades: if the token it points at is gone
      # (book deleted, or re-ingested with fresh offsets) the mark means nothing.
      t.references :token, null: false, foreign_key: { on_delete: :cascade }

      # Denormalised from the token's block so bookmarks can be listed in reading
      # order, and turned into a reader page, without joining two tables.
      t.integer :block_position, null: false

      t.timestamps
    end

    add_index :bookmarks, %i[user_id token_id], unique: true
    add_index :bookmarks, %i[user_id book_id block_position]
  end
end
