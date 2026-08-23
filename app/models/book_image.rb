class BookImage < ApplicationRecord
  belongs_to :book

  has_one_attached :file

  has_many :blocks, dependent: :nullify

  validates :checksum, presence: true
end
