class VocabEntry < ApplicationRecord
  STATUSES = %w[learning known ignored].freeze

  belongs_to :user
  belongs_to :lemma
  belongs_to :source_book, class_name: "Book", optional: true
  belongs_to :source_token, class_name: "Token", optional: true

  has_many :reviews, dependent: :delete_all

  validates :status, inclusion: { in: STATUSES }

  # "Ignored" words are ones the reader has decided not to study, so they are
  # excluded from both highlighting and the quiz.
  scope :active, -> { where(status: %w[learning known]) }
  scope :learning, -> { where(status: "learning") }
  scope :due, ->(at = Time.current) { active.where(due_at: ..at) }
  scope :with_lemma, -> { includes(:lemma) }
  # Everything the word bank list needs, so no row triggers its own queries.
  scope :for_listing, -> { includes(:lemma, :source_book, source_token: :block) }

  STATUSES.each do |value|
    define_method(:"#{value}?") { status == value }
  end

  def due?(at = Time.current)
    due_at.present? && due_at <= at
  end

  def never_reviewed?
    reps.zero?
  end

  # Distinct surface forms of this word the reader has actually met in their books.
  def encountered_forms(limit: 12)
    Token.where(lemma_id: lemma_id)
         .where(book_id: user.books.select(:id))
         .group(:surface)
         .order(Arel.sql("COUNT(*) DESC"))
         .limit(limit)
         .count
  end

  def occurrence_count
    Token.where(lemma_id: lemma_id, book_id: user.books.select(:id)).count
  end
end
