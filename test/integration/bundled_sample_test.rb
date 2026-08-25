require "test_helper"

# The bundled sample takes a different path through the reader than an uploaded book:
# its illustrations are committed assets rather than attachments, and its lemma ids were
# assigned at install time rather than by the ingester.
class BundledSampleTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
  end

  test "its illustrations are served from committed assets" do
    with_bundled_sample do
      get read_book_path(DemoBook.install_for(@user))

      assert_response :success
      # Raises rather than 404s if the asset is not committed, which is the point.
      assert_select "figure.reader__figure img[src*=?]", "demo/0000"
    end
  end

  test "its words open a card with the grammar recorded at export time" do
    with_bundled_sample do
      book = DemoBook.install_for(@user)
      token = book.blocks.in_order.first.tokens.last

      get token_path(token)

      assert_response :success
      assert_select ".word-card__surface", text: "duerme"
      assert_select ".word-card__lemma", text: /dormir/
    end
  end

  test "a word from the sample can be saved to the bank" do
    with_bundled_sample do
      book = DemoBook.install_for(@user)
      token = book.blocks.in_order.first.tokens.first

      assert_difference -> { @user.vocab_entries.count }, 1 do
        post add_words_path, params: { token_id: token.id }
      end

      entry = @user.vocab_entries.sole
      assert_equal "gato", entry.lemma.text
      assert_equal book, entry.source_book
      assert_equal({ "gato" => 1 }, entry.encountered_forms)
    end
  end
end
