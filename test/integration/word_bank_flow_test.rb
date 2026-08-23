require "test_helper"

class WordBankFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
    @fixture = build_annotated_book(@user)
  end

  test "adding a word from the reader saves it against the lemma, not the surface form" do
    assert_difference -> { @user.vocab_entries.count }, 1 do
      post add_words_path, params: { token_id: @fixture[:token].id }
    end

    assert_response :success
    entry = @user.vocab_entries.sole
    assert_equal "decir", entry.lemma.text
    assert_equal [ @fixture[:token].block_id, @fixture[:token].position ],
                 [ entry.source_block_id, entry.source_word_position ]
  end

  test "adding the same lemma twice does not duplicate the entry" do
    post add_words_path, params: { token_id: @fixture[:token].id }

    assert_no_difference -> { @user.vocab_entries.count } do
      post add_words_path, params: { token_id: @fixture[:token].id }
    end
  end

  test "a saved word is highlighted in the reader in a form it was not saved as" do
    post add_words_path, params: { token_id: @fixture[:token].id }
    get read_book_path(@fixture[:book])

    assert_select %(span.w--learning[data-token-id="#{@fixture[:token].id}"])
  end

  test "word bank lists the entry with its occurrence count" do
    post add_words_path, params: { token_id: @fixture[:token].id }
    get words_path

    assert_response :success
    assert_select ".word-row__lemma", text: "decir"
    assert_select ".word-row__meta", text: /Appears 1 time/
  end

  test "word bank search matches the Spanish lemma" do
    post add_words_path, params: { token_id: @fixture[:token].id }

    get words_path, params: { query: "decir" }
    assert_select ".word-row", count: 1

    get words_path, params: { query: "zzzz" }
    assert_select ".word-row", count: 0
  end

  test "the edit page shows where the word has been met" do
    post add_words_path, params: { token_id: @fixture[:token].id }
    entry = @user.vocab_entries.sole

    get word_path(entry)

    assert_response :success
    assert_select "h1", text: "decir"
    assert_select ".form-chip", text: /dijo/
  end

  test "the gloss is editable" do
    post add_words_path, params: { token_id: @fixture[:token].id }
    entry = @user.vocab_entries.sole

    patch word_path(entry), params: { vocab_entry: { gloss: "said", status: "learning" } }

    assert_equal "said", entry.reload.gloss
  end

  test "jumping back to the source passage lands on the word, not just its page" do
    post add_words_path, params: { token_id: @fixture[:token].id }
    get words_path

    anchor = ActionView::RecordIdentifier.dom_id(@fixture[:token], :w)

    assert_select "a", text: "In book" do |links|
      assert_equal read_book_path(@fixture[:book], page: 1, anchor: anchor), links.first["href"]
    end
  end

  test "removing a book keeps the words saved from it" do
    post add_words_path, params: { token_id: @fixture[:token].id }

    assert_no_difference -> { @user.vocab_entries.count } do
      delete book_path(@fixture[:book])
    end

    entry = @user.vocab_entries.sole
    assert_equal "decir", entry.lemma.text
    assert_nil entry.reload.source_book_id, "provenance should be cleared, not block the delete"
    assert_equal 0, Token.where(book_id: @fixture[:book].id).count
  end

  test "removing a book with a graded review does not orphan the review" do
    post add_words_path, params: { token_id: @fixture[:token].id }
    entry = @user.vocab_entries.sole
    Srs.grade!(entry, rating: "good", sentence: @fixture[:sentence])

    assert_nothing_raised { @fixture[:book].destroy }
    assert_equal 1, entry.reviews.count
    assert_nil entry.reviews.first.reload.sentence_id
  end

  test "removing from the reader swaps the button back to add" do
    post add_words_path, params: { token_id: @fixture[:token].id }
    entry = @user.vocab_entries.sole

    assert_difference -> { @user.vocab_entries.count }, -1 do
      delete word_path(entry, token_id: @fixture[:token].id)
    end

    assert_response :success
    assert_match "Add to word bank", response.body
  end
end
