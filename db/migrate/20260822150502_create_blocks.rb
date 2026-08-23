class CreateBlocks < ActiveRecord::Migration[8.0]
  def change
    create_table :blocks do |t|
      t.references :book, null: false, foreign_key: true
      t.references :book_image, foreign_key: true
      t.integer :position, null: false
      t.string :kind, null: false, default: "paragraph"
      t.integer :page_number
      t.text :text

      t.timestamps
    end

    add_index :blocks, [ :book_id, :position ], unique: true
  end
end
