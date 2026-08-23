class AddSchedulerStateToVocabEntries < ActiveRecord::Migration[8.0]
  def change
    # FSRS tracks which short-term learning step a card is on and how long the
    # last interval was; both are needed to resume a card faithfully.
    add_column :vocab_entries, :learning_steps, :integer, null: false, default: 0
    add_column :vocab_entries, :scheduled_days, :float, null: false, default: 0.0
  end
end
