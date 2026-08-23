require "test_helper"

class QuizFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
    @fixture = build_annotated_book(@user)
    post add_words_path, params: { token_id: @fixture[:token].id }
    @entry = @user.vocab_entries.sole
  end

  test "a new word appears as a card in the real sentence it came from" do
    get card_quiz_path

    assert_response :success
    assert_select ".quiz__prompt mark", text: "dijo"
  end

  test "grading schedules the word and logs the review" do
    assert_difference -> { @entry.reviews.count }, 1 do
      post answer_quiz_path, params: { entry_id: @entry.id, rating: "good" }
    end

    @entry.reload
    assert @entry.due_at.present?, "expected the word to be scheduled"
    assert_equal 1, @entry.reps
  end

  test "again and easy produce different intervals" do
    other = @user.vocab_entries.create!(lemma: Lemma.create!(text: "ver", pos: "VERB"), status: "learning")

    Srs.grade!(@entry, rating: "again")
    Srs.grade!(other, rating: "easy")

    assert @entry.reload.due_at < other.reload.due_at,
           "an 'again' grade should come back sooner than an 'easy' grade"
  end

  test "the queue empties once nothing is due" do
    Srs.grade!(@entry, rating: "easy")

    get card_quiz_path
    assert_match "Session complete", response.body
  end

  test "a quiz can be scoped to one book" do
    other_book = @user.books.create!(title: "Otro", status: "ready")
    outside = @user.vocab_entries.create!(
      lemma: Lemma.create!(text: "correr", pos: "VERB"),
      status: "learning",
      source_book: other_book
    )

    get card_quiz_path, params: { book_id: @fixture[:book].id }

    assert_response :success
    assert_no_match outside.lemma.text, response.body
  end
end
