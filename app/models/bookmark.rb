class Bookmark < ApplicationRecord
  belongs_to :user
  belongs_to :book
  belongs_to :token

  # Reading order, not the order they were placed: a bookmarks list is most useful
  # as a table of contents for your own marks.
  scope :in_reading_order, -> { order(:block_position, :token_id) }

  before_validation :copy_position_from_token

  validates :token_id, uniqueness: { scope: :user_id }

  def page
    book.page_for_block_position(block_position)
  end

  # The id BlockRenderer gives this word in the reader, used to scroll to it.
  def anchor
    ActionView::RecordIdentifier.dom_id(token, :w)
  end

  private

  def copy_position_from_token
    return if token.blank?

    self.book_id ||= token.book_id
    self.block_position ||= token.block.position
  end
end
