class CreateLemmas < ActiveRecord::Migration[8.0]
  def change
    create_table :lemmas do |t|
      t.string :text, null: false
      t.string :pos, null: false
      t.string :language, null: false, default: "es"

      t.timestamps
    end

    # The spine of the vocabulary: every token and every saved word joins through here,
    # which is what lets one bank entry match every conjugation in a book.
    add_index :lemmas, [ :language, :text, :pos ], unique: true
  end
end
