class CreateBookImages < ActiveRecord::Migration[8.0]
  def change
    create_table :book_images do |t|
      t.references :book, null: false, foreign_key: true
      t.string :checksum, null: false
      t.integer :width
      t.integer :height

      t.timestamps
    end

    # The same illustration is often repeated across many pages. Deduplicating on
    # content checksum keeps one stored file per distinct image.
    add_index :book_images, [ :book_id, :checksum ], unique: true
  end
end
