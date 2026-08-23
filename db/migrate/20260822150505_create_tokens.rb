class CreateTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :tokens do |t|
      t.references :book, null: false, foreign_key: true, index: false
      t.references :block, null: false, foreign_key: true, index: false
      t.references :sentence, null: false, foreign_key: true, index: false
      t.references :lemma, foreign_key: true, index: false
      t.integer :position, null: false
      t.integer :char_start, null: false
      t.integer :char_end, null: false
      t.string :surface, null: false
      t.string :pos
      t.jsonb :morph, null: false, default: {}
    end

    # Rendering a page walks tokens in order within each block.
    add_index :tokens, [ :block_id, :position ]
    # Occurrence counts, jump-back, and "forms I have encountered" all key off lemma.
    add_index :tokens, [ :lemma_id, :book_id ]
    add_index :tokens, :sentence_id
  end
end
