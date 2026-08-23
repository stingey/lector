require "application_system_test_case"

# Exercises the real pipeline end to end: an actual PDF goes through PyMuPDF and
# spaCy, then the reader is driven in a browser. Skipped when the sample book or
# the Python environment is not present.
class ReaderTest < ApplicationSystemTestCase
  SAMPLE_PDF = File.expand_path("~/Documents/Books/La sombra del viento.pdf")

  setup do
    skip "sample PDF not available" unless File.exist?(SAMPLE_PDF)
    skip "python env not available" unless File.executable?(Rails.root.join(".venv/bin/python"))

    @user = users(:one)
    @book = ingest_sample
    sign_in_through_the_form
  end

  test "reading, hovering, saving a word, and seeing every conjugation light up" do
    visit root_path
    assert_selector ".book-row__title", text: /La sombra/
    take_screenshot_named "library"

    visit read_book_path(@book)

    assert_selector "span.w", minimum: 50
    take_screenshot_named "reader"

    # Find a conjugated form of a common verb and open its card. Centred first so the
    # click cannot land under the fixed reader bar.
    word = first("span.w[data-lemma='decir']", minimum: 1)
    lemma_id = word["data-lemma-id"]
    page.execute_script("arguments[0].scrollIntoView({ block: 'center' })", word)
    word.click

    # Opening the card is a fetch of the frame plus a nested fetch for the gloss, so
    # it gets more room than Capybara's default wait.
    assert_selector ".word-card__surface", wait: 10
    assert_selector ".word-card__grammar"
    take_screenshot_named "word-card"

    click_on "+ Add to word bank"
    assert_selector ".badge", text: /new|learning/i

    # Every other form of the same word should now be highlighted, without a reload.
    assert_selector "span.w--learning[data-lemma-id='#{lemma_id}']", minimum: 2

    find(".word-card__close").click
    scroll_to_highlighted(lemma_id)
    take_screenshot_named "highlighted"

    visit words_path
    assert_selector ".word-row__lemma", text: "decir"
    assert_selector ".form-chip", minimum: 2
    take_screenshot_named "word-bank"

    visit quiz_path
    assert_selector ".quiz__prompt mark", text: "dijo"
    assert_no_selector ".quiz__grades"

    click_on "Show meaning"
    assert_selector ".quiz__grades"
    assert_no_selector "button", text: "Show meaning"
    take_screenshot_named "quiz"
  end

  private

  def ingest_sample
    book = @user.books.create!(title: "La sombra del viento")
    book.file.attach(io: File.open(SAMPLE_PDF), filename: "sombra.pdf", content_type: "application/pdf")

    with_env("INGEST_MAX_PAGES" => "14") { BookIngestor.new(book).call }
    book.reload
  end

  def with_env(values)
    previous = values.keys.index_with { |key| ENV[key] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end

  def sign_in_through_the_form
    visit new_session_path
    fill_in "email_address", with: @user.email_address
    fill_in "password", with: "password"
    click_on "Sign in"
    assert_selector ".topbar__brand"
  end

  # Centres the viewport on a paragraph containing several highlighted forms, so the
  # screenshot shows what a saved word actually looks like while reading.
  def scroll_to_highlighted(lemma_id)
    page.execute_script(<<~JS, lemma_id)
      const id = arguments[0]
      const marks = Array.from(document.querySelectorAll(`.w--learning[data-lemma-id="${id}"]`))
      const target = marks[Math.floor(marks.length / 2)] || marks[0]
      if (target) target.scrollIntoView({ block: "center" })
    JS
    sleep 0.3
  end

  def take_screenshot_named(name)
    path = Rails.root.join("tmp/screenshots/#{name}.png")
    FileUtils.mkdir_p(path.dirname)
    page.save_screenshot(path.to_s)
  end
end
