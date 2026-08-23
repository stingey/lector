require "test_helper"

class BookmarkFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    built = build_annotated_book(@user)
    @book = built[:book]
    @token = built[:token]
    sign_in @user
  end

  test "bookmarking a word records the page it sits on" do
    assert_difference -> { @user.bookmarks.count }, 1 do
      post bookmarks_path, params: { token_id: @token.id }
    end

    bookmark = @user.bookmarks.sole
    assert_equal @book, bookmark.book
    assert_equal @token.block.position, bookmark.block_position
    assert_equal 1, bookmark.page
  end

  test "bookmarking the same word twice leaves one mark" do
    post bookmarks_path, params: { token_id: @token.id }

    assert_no_difference -> { @user.bookmarks.count } do
      post bookmarks_path, params: { token_id: @token.id }
    end
  end

  test "the reader marks bookmarked words and leaves the rest alone" do
    @user.bookmarks.create!(token: @token)

    get read_book_path(@book)

    assert_select "span.w.w--bookmarked", 1
    assert_select "span##{ActionView::RecordIdentifier.dom_id(@token, :w)}.w--bookmarked"
  end

  test "the bookmarks page links back to the word itself, not just its page" do
    @user.bookmarks.create!(token: @token)

    get book_bookmarks_path(@book)

    assert_response :success
    assert_select "a", text: "Go there" do |links|
      assert_equal "/books/#{@book.id}/read?page=1##{ActionView::RecordIdentifier.dom_id(@token, :w)}",
                   links.first["href"]
    end
  end

  test "the bookmarks page shows the sentence the word was marked in" do
    @user.bookmarks.create!(token: @token)

    get book_bookmarks_path(@book)

    assert_select ".bookmark-row__context", text: /Ella dijo la verdad/
    assert_select ".bookmark-row__context mark", text: "dijo"
  end

  test "bookmarks are listed in reading order rather than when they were placed" do
    late_token = append_block_with_token(@book, position: 1, text: "Vino después.")

    @user.bookmarks.create!(token: late_token)
    @user.bookmarks.create!(token: @token)

    assert_equal [ @token.id, late_token.id ], @user.bookmarks.in_reading_order.map(&:token_id)
  end

  test "removing a bookmark from the list returns to the list" do
    bookmark = @user.bookmarks.create!(token: @token)

    assert_difference -> { @user.bookmarks.count }, -1 do
      delete bookmark_path(bookmark)
    end

    assert_redirected_to book_bookmarks_path(@book)
  end

  test "removing a bookmark from the word card returns the button, not a redirect" do
    bookmark = @user.bookmarks.create!(token: @token)

    delete bookmark_path(bookmark), headers: { "Turbo-Frame" => "bookmark_token_#{@token.id}" }

    assert_response :success
    assert_select "[data-bookmark-placed=false]"
  end

  test "another reader cannot bookmark a word in a book they do not own" do
    sign_in users(:two)

    assert_no_difference -> { Bookmark.count } do
      post bookmarks_path, params: { token_id: @token.id }
    end

    assert_response :not_found
  end

  test "deleting a book takes its bookmarks with it" do
    @user.bookmarks.create!(token: @token)

    assert_difference -> { Bookmark.count }, -1 do
      @book.destroy
    end
  end

  private

  # A second paragraph further into the book, so reading order is something other
  # than insertion order.
  def append_block_with_token(book, position:, text:)
    block = book.blocks.create!(position: position, kind: "paragraph", page_number: 1, text: text)
    sentence = book.sentences.create!(block: block, position: 0, char_start: 0, char_end: text.length, text: text)

    book.tokens.create!(block: block, sentence: sentence, position: 0,
                        char_start: 0, char_end: 4, surface: "Vino", pos: "VERB")
  end
end
