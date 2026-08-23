require "test_helper"

class VocabEntryTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @fixture = build_annotated_book(@user)
    @entry = @user.vocab_entries.create!(lemma: @fixture[:lemma], status: "learning")
  end

  test "occurrence count covers every book the reader owns" do
    assert_equal 1, @entry.occurrence_count

    build_annotated_book(@user, title: "Segundo")

    assert_equal 2, @entry.occurrence_count
  end

  test "occurrence count ignores books belonging to someone else" do
    build_annotated_book(users(:two), title: "Ajeno")

    assert_equal 1, @entry.occurrence_count
  end

  test "encountered forms merge the surfaces seen in each book" do
    build_annotated_book(@user, title: "Segundo")

    assert_equal({ "dijo" => 2 }, @entry.encountered_forms)
  end

  test "a word the reader has no book for has no occurrences" do
    entry = @user.vocab_entries.create!(
      lemma: Lemma.find_or_create_by!(text: "inexistente", pos: "NOUN", language: "es"),
      status: "learning"
    )

    assert_equal 0, entry.occurrence_count
    assert_empty entry.encountered_forms
  end
end
