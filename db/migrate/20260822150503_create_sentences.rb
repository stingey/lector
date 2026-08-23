class CreateSentences < ActiveRecord::Migration[8.0]
  def change
    create_table :sentences do |t|
      t.references :book, null: false, foreign_key: true
      t.references :block, null: false, foreign_key: true
      t.integer :position, null: false
      t.integer :char_start, null: false
      t.integer :char_end, null: false
      t.text :text, null: false
    end

    add_index :sentences, [ :block_id, :position ], unique: true
  end
end
