class BookImage < ApplicationRecord
  belongs_to :book

  has_one_attached :file

  has_many :blocks, dependent: :nullify

  validates :checksum, presence: true

  # What image_tag should draw. The bundled sample's illustrations are committed to the
  # repo and served as assets, so they outlive a restart on a host with no object
  # storage; an uploaded book's are attachments as usual.
  def source
    return static_path if static_path.present?

    file if file.attached?
  end
end
