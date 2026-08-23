require "application_system_test_case"

# Zooming should read like a larger-print edition of the same book: the column grows
# with the type so the line length stays put. The bug this pins was a measure in rem,
# which is relative to the root font size and so never scaled, squeezing the same
# column into more and more lines.
class ReadingSizeTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @fixture = build_annotated_book(@user)
    sign_in_through_the_form
    visit read_book_path(@fixture[:book])
  end

  test "the column widens with the text so the line length holds steady" do
    small = measure { 3.times { click_on "A−" } }
    large = measure { 6.times { click_on "A+" } }

    assert large[:font] > small[:font] * 1.3, "expected the text to get meaningfully bigger"
    assert large[:width] > small[:width], "expected the column to widen with the text"

    # The characters-per-line figure is the thing that makes long-form reading
    # comfortable, so it should barely move across the whole zoom range.
    ratio = large[:chars] / small[:chars].to_f
    assert ratio.between?(0.85, 1.15),
           "characters per line drifted from #{small[:chars].round} to #{large[:chars].round}"
  end

  test "the chosen size survives a page change" do
    3.times { click_on "A+" }
    chosen = font_size

    visit read_book_path(@fixture[:book])

    assert_in_delta chosen, font_size, 0.01
  end

  test "zooming stops at the ends of the range instead of running away" do
    biggest = zoom_to_the_end("A+")
    smallest = zoom_to_the_end("A−")

    assert biggest > smallest
    assert smallest > 8, "the text should never shrink to nothing"
    assert biggest < 64, "the text should never grow without bound"
  end

  private

  # Presses until the size holds still, which is the clamp doing its job. Pressed a
  # fixed number of times, the driver can dispatch faster than the click handler runs,
  # and a dropped press is indistinguishable from having reached the end of the range.
  # Two unchanged presses in a row is the clamp; one is a lost click.
  def zoom_to_the_end(button, presses: 24)
    size = font_size
    unchanged = 0

    presses.times do
      click_on button
      current = font_size
      unchanged = current == size ? unchanged + 1 : 0
      size = current
      break if unchanged >= 2
    end

    size
  end

  def measure
    yield
    { font: font_size, width: column_width, chars: characters_per_line }
  end

  def font_size
    page.evaluate_script("parseFloat(getComputedStyle(document.querySelector('.reader')).fontSize)")
  end

  def column_width
    page.evaluate_script("document.querySelector('.reader').getBoundingClientRect().width")
  end

  # Width of the text area divided by the width of one character in the reading font.
  def characters_per_line
    page.evaluate_script(<<~JS)
      (() => {
        const reader = document.querySelector(".reader")
        const style = getComputedStyle(reader)
        const inner = reader.clientWidth -
          parseFloat(style.paddingLeft) - parseFloat(style.paddingRight)

        const probe = document.createElement("span")
        probe.textContent = "x".repeat(100)
        probe.style.whiteSpace = "pre"
        reader.appendChild(probe)
        const advance = probe.getBoundingClientRect().width / 100
        probe.remove()

        return inner / advance
      })()
    JS
  end

  def sign_in_through_the_form
    visit new_session_path
    fill_in "email_address", with: @user.email_address
    fill_in "password", with: "password"
    click_on "Sign in"
    assert_selector ".topbar__brand"
  end
end
