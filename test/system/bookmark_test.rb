require "application_system_test_case"

# Bookmarking is a round trip through the browser: place a mark from the word card,
# see the ribbon appear on the word without a reload, leave the page, and come back
# to that exact word from the bookmarks list.
class BookmarkTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @book = build_long_book(@user)
    sign_in_through_the_form
  end

  test "placing a bookmark, finding it in the list, and following it back" do
    visit_reader(@book, page: 2)

    word = find("span.w", match: :first)
    token_id = word["data-token-id"]
    page.execute_script("arguments[0].scrollIntoView({ block: 'center' })", word)
    word.click

    assert_selector ".word-card__surface", wait: 10
    click_on "Bookmark this spot"

    # The ribbon appears on the word underneath the card, without reloading the page.
    assert_selector "span.w--bookmarked[data-token-id='#{token_id}']"
    assert_selector "span.w--bookmarked", count: 1
    take_screenshot_named "bookmark-placed"

    find(".word-card__close").click
    take_screenshot_named "bookmark-ribbon"

    click_on "Bookmarks 1"

    assert_selector ".bookmark-row", count: 1
    assert_selector ".bookmark-row__meta", text: /Page 2/
    take_screenshot_named "bookmarks-list"

    click_on "Go there"

    # Back on the right page, with the marked word highlighted for a moment so it can
    # be found in a wall of prose.
    assert_selector ".reader-bar", text: "2 / 3"
    assert_selector "span.w--found[data-token-id='#{token_id}']"
  end

  test "removing a bookmark clears the ribbon from the word" do
    visit_reader(@book)

    word = find("span.w", match: :first)
    page.execute_script("arguments[0].scrollIntoView({ block: 'center' })", word)
    word.click

    assert_selector ".word-card__surface", wait: 10
    click_on "Bookmark this spot"
    assert_selector "span.w--bookmarked"

    click_on "Remove bookmark"
    assert_no_selector "span.w--bookmarked"
    assert_selector "button", text: "Bookmark this spot"
  end

  test "with no bookmark the library offers a plain Continue at the last page read" do
    visit_reader(@book, page: 3)
    visit root_path

    assert_selector ".book-row__meta", text: /page 81 of/
    assert_no_link "Continue from bookmark"

    click_on "Continue"
    assert_selector ".reader-bar", text: "3 / 3"
  end

  test "with a bookmark the library says so and goes to the marked word" do
    token_id = place_bookmark_on(2)

    # Read on past the mark: the button names the bookmark, so it still goes there.
    visit_reader(@book, page: 3)
    visit root_path

    click_on "Continue from bookmark"

    assert_selector ".reader-bar", text: "2 / 3"
    assert_selector "span.w--found[data-token-id='#{token_id}']"
  end

  test "a book that has never been opened offers nothing to continue from" do
    visit root_path

    assert_no_link "Continue"
    assert_selector ".book-row__meta", text: /120 pages/
  end

  private

  # Places a mark on the first word of a page the way a reader would, and returns the
  # token id so the caller can check it is the word we land back on.
  def place_bookmark_on(reader_page)
    visit_reader(@book, page: reader_page)

    word = find("span.w", match: :first)
    page.execute_script("arguments[0].scrollIntoView({ block: 'center' })", word)
    word.click

    assert_selector ".word-card__surface", wait: 10
    click_on "Bookmark this spot"
    assert_selector "span.w--bookmarked"

    word["data-token-id"]
  end

  # Three reader pages of prose, so bookmarks have somewhere to point other than the
  # first screen.
  def build_long_book(user)
    count = Book::BLOCKS_PER_PAGE * 3
    book = user.books.create!(title: "Cuentos", status: "ready", block_count: count, page_count: count)

    count.times do |index|
      build_block_with_words(book, position: index,
                             text: "Bloque #{index + 1}: ella dijo la verdad.",
                             words: [ { surface: "ella", lemma: "ella", pos: "PRON" } ])
    end

    book
  end

  def sign_in_through_the_form
    visit new_session_path
    fill_in "email_address", with: @user.email_address
    fill_in "password", with: "password"
    click_on "Sign in"
    assert_selector ".topbar__brand"
  end

  def take_screenshot_named(name)
    path = Rails.root.join("tmp/screenshots/#{name}.png")
    FileUtils.mkdir_p(path.dirname)
    page.save_screenshot(path.to_s)
  end
end
