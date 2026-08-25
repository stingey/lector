require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]

  # Opens a book and waits for the reader's Stimulus controller to attach its listeners.
  # Waiting for the prose instead is the wrong signal: it is server rendered, so it is
  # already there while a keystroke or click still has nothing behind it.
  def visit_reader(book, **options)
    visit read_book_path(book, **options)
    assert_selector "[data-reader-ready]", visible: :all
  end

  # The browser is reused across tests, and the reader stores the chosen reading size in
  # localStorage, so without this a test inherits whatever zoom the previous one left
  # behind. Fails quietly on about:blank, where storage is not reachable.
  teardown do
    page.execute_script("localStorage.clear()")
  rescue StandardError
    nil
  end
end
