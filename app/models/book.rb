class Book < ApplicationRecord
  STATUSES = %w[pending processing ready failed].freeze

  # How many blocks make up one screen of reading.
  BLOCKS_PER_PAGE = 40

  belongs_to :user

  has_one_attached :file

  has_many :blocks, -> { order(:position) }
  has_many :sentences
  has_many :book_lemmas
  has_many :book_images, dependent: :destroy
  has_many :reading_progresses, dependent: :delete_all
  has_many :bookmarks, dependent: :delete_all

  # Content is torn down explicitly rather than by :dependent, which would delete in the
  # wrong order and instantiate every row it touched.
  before_destroy :purge_content!, prepend: true

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :ready, -> { where(status: "ready") }
  scope :recent, -> { order(created_at: :desc) }

  STATUSES.each do |value|
    define_method(:"#{value}?") { status == value }
  end

  # Deleted innermost first: sentences reference blocks. Used both when removing a book
  # and when re-ingesting one. Bookmarks go with the blocks by cascade, since
  # re-ingesting changes every offset they point at.
  def purge_content!
    BookLemma.where(book_id: id).delete_all
    Sentence.where(book_id: id).delete_all
    Block.where(book_id: id).delete_all
  end

  def progress_for(user)
    reading_progresses.find_or_initialize_by(user: user)
  end

  def total_pages
    [ (block_count / BLOCKS_PER_PAGE.to_f).ceil, 1 ].max
  end

  def page_for_block_position(position)
    (position.to_i / BLOCKS_PER_PAGE) + 1
  end
end
