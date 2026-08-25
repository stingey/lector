require "application_system_test_case"

# The card is a popover on the word, not a panel at the edge of the screen, so where it
# lands is the feature. These check the geometry rather than just that it opened.
class WordCardPlacementTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @book = build_wordy_book(@user)
    sign_in_through_the_form
    visit_reader(@book)
  end

  test "the card opens directly under the word that was clicked" do
    word = click_word_near_top
    card = placed_card

    assert card[:top] >= word[:bottom], "card should sit below the word"
    assert card[:top] - word[:bottom] < 24, "card should be right under the word, not adrift"
    assert word[:left] >= card[:left] && word[:right] <= card[:right],
           "the word should fall within the card's width"
  end

  test "the caret points at the word" do
    word = click_word_near_top
    card = placed_card
    caret = card[:left] + caret_offset
    centre = word[:left] + word[:width] / 2

    assert_in_delta centre, caret, 2, "the caret should line up with the middle of the word"
  end

  test "a word near the bottom of the screen gets its card above instead" do
    word = click_word_near_bottom
    card = placed_card

    assert_selector ".word-card--above"
    assert card[:bottom] <= word[:top], "card should sit above the word"
    assert card[:top] > 0, "card should stay on screen"
  end

  test "the card stays with its passage when the page scrolls" do
    click_word_near_top

    before = placed_card[:top]
    page.execute_script("window.scrollBy(0, 200)")
    after = rect(".word-card")[:top]

    assert_in_delta before - 200, after, 2, "the card should scroll with the text, not float"
  end

  test "clicking another word moves the card to it without closing first" do
    click_word_near_top
    placed_card
    first_surface = find(".word-card__surface").text

    # A word on the same line, which the open card sits below rather than over. A card
    # covering the text really does block clicks, which is why this is not just any word.
    moved = click_word("words[2]")

    assert_selector ".word-card__surface", text: "verdad", wait: 10
    assert_equal 1, all(".word-card").size
    assert_not_equal first_surface, find(".word-card__surface").text

    card = placed_card
    assert card[:top] >= moved[:bottom], "the card should have followed the new word"
    assert_in_delta moved[:left] + moved[:width] / 2, card[:left] + caret_offset, 2
  end

  test "clicking away closes the card" do
    click_word_near_top
    placed_card

    page.execute_script("document.querySelector('.topbar').click()")

    assert_no_selector ".word-card"
    assert_no_selector ".w--active"
  end

  private

  # The card is hidden until the controller has placed it, so waiting for that class is
  # what makes these measurements meaningful rather than racing the positioning.
  def placed_card
    assert_selector ".word-card--placed", wait: 10
    rect(".word-card")
  end

  def click_word_near_top
    page.execute_script("window.scrollTo(0, 0)")
    click_word("words[0]")
  end

  # The lowest word still on screen, which is where the flip has to happen.
  def click_word_near_bottom
    click_word(<<~JS)
      words.reverse().find((word) => {
        const box = word.getBoundingClientRect()
        return box.top > limit * 0.7 && box.bottom < limit
      })
    JS
  end

  # Clicks are dispatched from JavaScript rather than through Selenium, which scrolls an
  # element to the middle of the viewport first: that would move a word away from the
  # screen edge these tests are about. The app sees an ordinary bubbling click either
  # way, and reader_test covers a real pointer click.
  def click_word(expression)
    box = page.evaluate_script(<<~JS)
      (() => {
        const limit = document.documentElement.clientHeight
        const words = Array.from(document.querySelectorAll("span.w"))
        const target = #{expression}
        if (!target) return null

        target.click()
        const box = target.getBoundingClientRect()
        return { top: box.top, bottom: box.bottom, left: box.left, right: box.right, width: box.width }
      })()
    JS

    assert box, "expected to find a word to click"
    box.transform_keys(&:to_sym)
  end

  def caret_offset
    page.evaluate_script(
      "parseFloat(getComputedStyle(document.querySelector('.word-card')).getPropertyValue('--caret-x'))"
    )
  end

  def rect(selector)
    page.evaluate_script(<<~JS).transform_keys(&:to_sym)
      (() => {
        const box = document.querySelector(#{selector.to_json}).getBoundingClientRect()
        return { top: box.top, bottom: box.bottom, left: box.left, right: box.right, width: box.width }
      })()
    JS
  end

  # Enough prose to fill more than one screen, so there are words at both ends of the
  # viewport to click.
  def build_wordy_book(user)
    count = 30
    book = user.books.create!(title: "Prosa", status: "ready", block_count: count, page_count: count)

    count.times do |index|
      build_block_with_words(
        book,
        position: index,
        text: "Bloque #{index + 1}: ella dijo la verdad sobre el jardín escondido.",
        words: %w[ella dijo verdad jardín].map { |surface| { surface: surface, lemma: surface, pos: "NOUN" } }
      )
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
end
