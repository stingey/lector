class Review < ApplicationRecord
  # FSRS grades: 1 Again, 2 Hard, 3 Good, 4 Easy.
  RATINGS = { again: 1, hard: 2, good: 3, easy: 4 }.freeze

  belongs_to :vocab_entry
  belongs_to :sentence, optional: true

  validates :rating, inclusion: { in: RATINGS.values }

  scope :chronological, -> { order(:reviewed_at) }

  def rating_name
    RATINGS.key(rating).to_s
  end
end
