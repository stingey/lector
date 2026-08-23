require "application_system_test_case"

# Illustrated books broke assumptions that a plain novel never tested: images have to
# stay where they fall (they often mark chapters), and callout boxes set in all-caps
# display type are prose, not headings.
class IllustratedBookTest < ApplicationSystemTestCase
  SAMPLE_PDF = File.expand_path("~/Documents/Books/Trilogia La puerta de los tres - Sonia Fernandez-Vidal.pdf")
  RIDDLE = "IMAGINAOS UNA CALLE"

  setup do
    skip "illustrated sample not available" unless File.exist?(SAMPLE_PDF)
    skip "python env not available" unless File.executable?(Rails.root.join(".venv/bin/python"))

    @user = users(:one)
    @book = ingest_sample
    sign_in_through_the_form
  end

  test "images stay interleaved with the text instead of piling up at the front" do
    blocks = @book.blocks.limit(40).to_a
    kinds = blocks.map(&:kind)

    assert_includes kinds, "image"
    refute_equal "image", kinds.uniq.first if kinds.uniq.one?

    # The give-away symptom was every image sorting ahead of every paragraph.
    first_text = blocks.index { |block| block.kind != "image" }
    last_image = blocks.rindex { |block| block.kind == "image" }
    assert last_image > first_text,
           "expected at least one image to fall after the text, not all of them before it"
  end

  test "a riddle set in display capitals is one tappable paragraph, not a run of headings" do
    block = @book.blocks.find_by("text LIKE ?", "%#{RIDDLE}%")
    assert block.present?, "the riddle should survive ingest"
    assert_equal "paragraph", block.kind

    visit read_book_path(@book, page: @book.page_for_block_position(block.position))

    assert_selector "p", text: /#{RIDDLE}/
    assert_selector "p span.w", text: "IMAGINAOS"
    take_screenshot_named "illustrated-riddle"

    # The whole riddle reads as continuous prose rather than broken lines.
    assert_match "¿CÓMO HA CONSEGUIDO VERLO?", block.text
  end

  test "words inside a heading can still be looked up" do
    heading = @book.blocks.where(kind: "heading").find { |block| block.tokens.any? }
    assert heading.present?, "expected a heading with word tokens"

    visit read_book_path(@book, page: @book.page_for_block_position(heading.position))

    assert_selector "h2.reader__heading span.w"
  end

  test "the source watermark is stripped from the prose" do
    assert_equal 0, @book.blocks.where("text ILIKE ?", "%OceanofPDF%").count
  end

  private

  def ingest_sample
    book = @user.books.create!(title: "La Puerta de los Tres Cerrojos")
    book.file.attach(io: File.open(SAMPLE_PDF), filename: "puerta.pdf", content_type: "application/pdf")

    # Far enough in to include the illustrated front matter and the first riddle.
    with_env("INGEST_MAX_PAGES" => "18") { BookIngestor.new(book).call }
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

  def take_screenshot_named(name)
    path = Rails.root.join("tmp/screenshots/#{name}.png")
    FileUtils.mkdir_p(path.dirname)
    page.save_screenshot(path.to_s)
  end
end
