require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]

  # The browser is reused across tests, and the reader stores the chosen reading size in
  # localStorage, so without this a test inherits whatever zoom the previous one left
  # behind. Fails quietly on about:blank, where storage is not reachable.
  teardown do
    page.execute_script("localStorage.clear()")
  rescue StandardError
    nil
  end
end
