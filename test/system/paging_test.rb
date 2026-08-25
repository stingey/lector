require "application_system_test_case"

class PagingTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @book = build_paged_book(@user)
    sign_in_through_the_form
  end

  test "the right arrow turns to the next page and the left arrow comes back" do
    visit_reader(@book)
    assert_text "Bloque 1"

    send_key :right
    assert_text "Bloque 41"
    assert_no_text "Bloque 1"

    send_key :left
    assert_text "Bloque 1"
  end

  test "arrows stop at the ends of the book instead of wrapping" do
    visit_reader(@book)

    send_key :left
    assert_text "Bloque 1 de la prueba."

    visit_reader(@book, page: @book.total_pages)
    send_key :right
    assert_selector ".reader-bar", text: "#{@book.total_pages} / #{@book.total_pages}"
  end

  test "arrows do not turn the page while typing in a field" do
    visit words_path
    fill_in "query", with: "hola"
    send_key :right

    assert_field "query", with: "hola"
  end

  private

  # Three reader pages worth of blocks, each labelled so the page in view is obvious.
  def build_paged_book(user)
    count = Book::BLOCKS_PER_PAGE * 3
    book = user.books.create!(title: "Paginado", status: "ready", block_count: count, page_count: count)

    count.times do |index|
      book.blocks.create!(position: index, kind: "paragraph", page_number: index + 1,
                          text: "Bloque #{index + 1} de la prueba.")
    end

    book
  end

  def send_key(key)
    page.driver.browser.action.send_keys(key).perform
  end

  def sign_in_through_the_form
    visit new_session_path
    fill_in "email_address", with: @user.email_address
    fill_in "password", with: "password"
    click_on "Sign in"
    assert_selector ".topbar__brand"
  end
end
