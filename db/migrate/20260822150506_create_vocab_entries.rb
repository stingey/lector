class CreateVocabEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :vocab_entries do |t|
      t.references :user, null: false, foreign_key: true
      t.references :lemma, null: false, foreign_key: true
      t.references :source_book, foreign_key: { to_table: :books }
      t.references :source_token, foreign_key: { to_table: :tokens }

      t.string :status, null: false, default: "learning"
      t.text :gloss
      t.text :note

      # FSRS scheduler state
      t.string :fsrs_state, null: false, default: "new"
      t.float :stability
      t.float :difficulty
      t.datetime :due_at
      t.datetime :last_reviewed_at
      t.integer :reps, null: false, default: 0
      t.integer :lapses, null: false, default: 0

      t.timestamps
    end

    add_index :vocab_entries, [ :user_id, :lemma_id ], unique: true
    add_index :vocab_entries, [ :user_id, :due_at ]
    add_index :vocab_entries, [ :user_id, :status ]
  end
end
