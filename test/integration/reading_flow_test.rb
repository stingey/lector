require "test_helper"

class ReadingFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
    @fixture = build_annotated_book(@user)
  end

  test "library lists a ready book" do
    get root_path

    assert_response :success
    assert_select ".book-row__title", text: /Prueba/
  end

  test "reader wraps each word in a span carrying its lemma and grammar" do
    get read_book_path(@fixture[:book])

    assert_response :success
    assert_select "span.w", minimum: 4

    token = @fixture[:token]
    assert_select %(span.w[data-token-id="#{token.id}"]) do |elements|
      element = elements.first
      assert_equal "dijo", element.text
      assert_equal "decir", element["data-lemma"]
      assert_equal "verb - preterite, 3rd person singular", element["data-grammar"]
    end
  end

  test "reader preserves the original paragraph text exactly" do
    get read_book_path(@fixture[:book])

    paragraph = Nokogiri::HTML(response.body).at_css(".reader p")
    assert_equal @fixture[:block].text, paragraph.text
  end

  test "word card renders grammar without needing a translator" do
    get token_path(@fixture[:token])

    assert_response :success
    assert_select ".word-card__surface", text: "dijo"
    assert_select ".word-card__grammar", text: /preterite/
    assert_select ".word-card__sentence mark", text: "dijo"
  end

  test "gloss frame degrades gracefully when no provider is configured" do
    get gloss_token_path(@fixture[:token])

    assert_response :success
    assert_match "TRANSLATOR_API_KEY", response.body
  end
end
