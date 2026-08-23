class CreateReviews < ActiveRecord::Migration[8.0]
  def change
    create_table :reviews do |t|
      t.references :vocab_entry, null: false, foreign_key: true
      t.references :sentence, foreign_key: true

      t.integer :rating, null: false
      t.string :state_before
      t.float :stability_after
      t.float :difficulty_after
      t.float :elapsed_days
      t.float :scheduled_days
      t.datetime :reviewed_at, null: false
    end

    # Full review history is retained so FSRS parameters can be optimized later.
    add_index :reviews, [ :vocab_entry_id, :reviewed_at ]
  end
end
