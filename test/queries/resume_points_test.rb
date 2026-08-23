require "test_helper"

class ResumePointsTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @book = build_paged_book(@user)
  end

  test "a book that has never been opened has no resume point" do
    assert_empty ResumePoints.for(@user, [ @book ])
  end

  test "without bookmarks it resumes at the last page turned to" do
    record_progress(page: 3)

    point = resume
    assert_equal 3, point.page
    assert_nil point.anchor
    assert_equal "Continue", point.label
  end

  test "a bookmark wins over the last page turned to, and lands on the word" do
    record_progress(page: 3)
    token = token_on(page: 3, offset: 5)
    @user.bookmarks.create!(token: token)

    point = resume
    assert_equal 3, point.page
    assert_equal ActionView::RecordIdentifier.dom_id(token, :w), point.anchor
    assert_equal "Continue from bookmark", point.label
  end

  # The button names the bookmark, so it has to go there even when reading has moved on.
  test "a bookmark still wins after you have read past it" do
    token = token_on(page: 2, offset: 5)
    @user.bookmarks.create!(token: token)
    record_progress(page: 5)

    point = resume
    assert_equal 2, point.page
    assert_equal ActionView::RecordIdentifier.dom_id(token, :w), point.anchor
    assert_equal "Continue from bookmark", point.label
  end

  test "a bookmark counts on its own when no page has been turned yet" do
    token = token_on(page: 4, offset: 0)
    @user.bookmarks.create!(token: token)

    point = resume
    assert_equal 4, point.page
    assert_equal ActionView::RecordIdentifier.dom_id(token, :w), point.anchor
  end

  test "the newest bookmark is the one that counts" do
    @user.bookmarks.create!(token: token_on(page: 2, offset: 1), created_at: 2.days.ago)
    newest = token_on(page: 4, offset: 1)
    @user.bookmarks.create!(token: newest, created_at: 1.hour.ago)

    assert_equal ActionView::RecordIdentifier.dom_id(newest, :w), resume.anchor
  end

  test "it reports the book's own printed page number for the position" do
    record_progress(page: 3)

    # Page 3 of the reader starts at block 80, and each block was given the page number
    # of its own index, so the printed page is 81.
    assert_equal 81, resume.book_page
  end

  test "one call covers a whole library and keeps each book's own position" do
    other = build_paged_book(@user, title: "Otro")
    record_progress(page: 2)
    other.reading_progresses.create!(user: @user, block_position: (5 - 1) * Book::BLOCKS_PER_PAGE)

    points = ResumePoints.for(@user, [ @book, other ])

    assert_equal 2, points[@book.id].page
    assert_equal 5, points[other.id].page
  end

  test "another reader's marks and position do not leak in" do
    stranger = users(:two)
    stranger.bookmarks.create!(token: token_on(page: 4, offset: 0))
    @book.reading_progresses.create!(user: stranger, block_position: 200)

    assert_empty ResumePoints.for(@user, [ @book ])
  end

  private

  def resume
    ResumePoints.for(@user, [ @book ]).fetch(@book.id)
  end

  def record_progress(page:)
    @book.reading_progresses.create!(user: @user, block_position: (page - 1) * Book::BLOCKS_PER_PAGE)
  end

  def token_on(page:, offset:)
    position = (page - 1) * Book::BLOCKS_PER_PAGE + offset
    @book.tokens.joins(:block).find_by!(blocks: { position: position })
  end

  # Six reader pages, one token per block, each block carrying its own page number.
  def build_paged_book(user, title: "Paginado")
    count = Book::BLOCKS_PER_PAGE * 6
    book = user.books.create!(title: title, status: "ready", block_count: count, page_count: count)

    count.times do |index|
      text = "Bloque #{index + 1}: ella habló."
      block = book.blocks.create!(position: index, kind: "paragraph", page_number: index + 1, text: text)
      sentence = book.sentences.create!(block: block, position: 0, char_start: 0,
                                        char_end: text.length, text: text)
      start = text.index("ella")
      book.tokens.create!(block: block, sentence: sentence, position: 0,
                          char_start: start, char_end: start + 4, surface: "ella", pos: "PRON")
    end

    book
  end
end
