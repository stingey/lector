class CreateBooks < ActiveRecord::Migration[8.0]
  def change
    create_table :books do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.string :author
      t.string :language, null: false, default: "es"
      t.string :status, null: false, default: "pending"
      t.string :source_filename
      t.string :checksum
      t.integer :page_count
      t.integer :block_count, null: false, default: 0
      t.integer :word_count, null: false, default: 0
      t.text :ingest_error
      t.datetime :ingested_at

      t.timestamps
    end

    add_index :books, [ :user_id, :checksum ], unique: true, where: "checksum IS NOT NULL"
    add_index :books, [ :user_id, :status ]
  end
end
