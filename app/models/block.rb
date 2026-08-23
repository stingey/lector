class Block < ApplicationRecord
  KINDS = %w[paragraph heading image].freeze

  belongs_to :book
  belongs_to :book_image, optional: true

  has_many :sentences, -> { order(:position) }, dependent: :delete_all
  has_many :tokens, -> { order(:position) }, dependent: :delete_all

  validates :kind, inclusion: { in: KINDS }

  scope :in_order, -> { order(:position) }

  KINDS.each do |value|
    define_method(:"#{value}?") { kind == value }
  end
end
