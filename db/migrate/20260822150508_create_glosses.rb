class CreateGlosses < ActiveRecord::Migration[8.0]
  def change
    create_table :glosses do |t|
      t.references :lemma, null: false, foreign_key: true
      t.string :surface, null: false
      t.string :sentence_digest, null: false
      t.jsonb :payload, null: false, default: {}
      t.string :model

      t.timestamps
    end

    # Each (word form, sentence) pair is paid for once, then served from here forever.
    add_index :glosses, [ :lemma_id, :surface, :sentence_digest ], unique: true, name: "index_glosses_on_lookup"
  end
end
