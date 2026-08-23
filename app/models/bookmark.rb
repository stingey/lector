# A place in a book, marked on one word.
#
# Stored as the block plus the word's position inside it, with the block's position
# copied alongside so the reader can ask "which bookmarks fall on this page" with one
# indexed range query instead of a list of every word on screen.
class Bookmark < ApplicationRecord
  belongs_to :user
  belongs_to :book
  belongs_to :block

  scope :in_reading_order, -> { order(:block_position, :word_position) }

  before_validation :copy_position_from_block

  validates :word_position, presence: true, uniqueness: { scope: %i[user_id block_id] }

  # Marking is done by handing over a word; the block and offset are what get stored.
  def token=(token)
    self.block = token.block
    self.word_position = token.position
  end

  def token
    block&.tokens&.find_by(position: word_position)
  end

  def page
    book.page_for_block_position(block_position)
  end

  def anchor
    word = token
    word && ActionView::RecordIdentifier.dom_id(word, :w)
  end

  private

  def copy_position_from_block
    return if block.blank?

    self.book_id ||= block.book_id
    self.block_position ||= block.position
  end
end
