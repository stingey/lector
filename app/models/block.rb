class Block < ApplicationRecord
  KINDS = %w[paragraph heading image].freeze

  belongs_to :book
  belongs_to :book_image, optional: true

  has_many :sentences, -> { order(:position) }, dependent: :delete_all

  validates :kind, inclusion: { in: KINDS }

  scope :in_order, -> { order(:position) }

  KINDS.each do |value|
    define_method(:"#{value}?") { kind == value }
  end

  # The words of this block. `words` is the raw jsonb column and nothing outside this
  # model should read it directly.
  def tokens
    @tokens ||= Array(words).map { |data| Token.from_data(self, data) }
  end

  def token_at(position)
    tokens.detect { |token| token.position == position }
  end

  def lemma_ids
    tokens.filter_map(&:lemma_id).uniq
  end
end
