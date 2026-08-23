class CreateReadingProgresses < ActiveRecord::Migration[8.0]
  def change
    create_table :reading_progresses do |t|
      t.references :user, null: false, foreign_key: true
      t.references :book, null: false, foreign_key: true
      t.integer :block_position, null: false, default: 0

      t.timestamps
    end

    add_index :reading_progresses, [ :user_id, :book_id ], unique: true
  end
end
