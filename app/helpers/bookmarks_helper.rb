module BookmarksHelper
  # A bookmark resolves to a page plus the id of the word itself, so following it
  # lands on the word rather than somewhere on the right page.
  def reader_path_for(bookmark)
    read_book_path(bookmark.book, page: bookmark.page, anchor: bookmark.anchor)
  end
end
