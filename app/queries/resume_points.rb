# Where a book should open when you pick it out of the library.
#
# Your newest bookmark wins if you have one, and lands on the exact word; otherwise the
# page you last turned to, which is recorded automatically. The bookmark wins even if
# you have since read past it, because the library says so on the button: a control
# labelled "Continue from bookmark" has to go to the bookmark or it is lying.
class ResumePoints
  Point = Data.define(:page, :anchor, :book_page, :from_bookmark) do
    def path_options
      anchor.present? ? { page: page, anchor: anchor } : { page: page }
    end

    def label
      from_bookmark ? "Continue from bookmark" : "Continue"
    end
  end

  def self.for(user, books)
    new(user, books).call
  end

  def initialize(user, books)
    @user = user
    @books = Array(books).index_by(&:id)
  end

  def call
    return {} if books.empty?

    positions = resolved_positions
    pages = book_page_numbers(positions.transform_values { |target| target[:block_position] })

    positions.transform_values do |target|
      book = books.fetch(target[:book_id])

      Point.new(
        page: book.page_for_block_position(target[:block_position]),
        anchor: target[:anchor],
        book_page: pages[target[:book_id]],
        from_bookmark: target[:anchor].present?
      )
    end
  end

  private

  attr_reader :user, :books

  def resolved_positions
    progress = progress_positions
    marks = newest_bookmarks

    books.each_value.with_object({}) do |book, targets|
      mark = marks[book.id]
      position = progress[book.id]

      target =
        if mark
          { book_id: book.id, block_position: mark.block_position, anchor: mark.anchor }
        elsif position&.positive?
          { book_id: book.id, block_position: position, anchor: nil }
        end

      targets[book.id] = target if target
    end
  end

  def progress_positions
    user.reading_progresses.where(book_id: books.keys).pluck(:book_id, :block_position).to_h
  end

  # The most recently placed mark in each book. Ordering ascending and indexing by book
  # leaves the newest one, since index_by keeps the last value it sees.
  def newest_bookmarks
    user.bookmarks.where(book_id: books.keys).order(:created_at, :id).includes(:block).index_by(&:book_id)
  end

  # The book's own printed page number for each position, so the library can say where
  # you are in the terms the book itself uses.
  def book_page_numbers(positions_by_book)
    return {} if positions_by_book.empty?

    rows = Block.where(book_id: positions_by_book.keys, position: positions_by_book.values)
                .pluck(:book_id, :position, :page_number)

    rows.filter_map { |book_id, position, page| [ book_id, page ] if positions_by_book[book_id] == position }.to_h
  end
end
