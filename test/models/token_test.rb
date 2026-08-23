require "test_helper"

class TokenTest < ActiveSupport::TestCase
  setup do
    @fixture = build_annotated_book(users(:one))
    @block = @fixture[:block]
    @token = @fixture[:token]
  end

  test "a word is identified by its block and its position in it" do
    assert_equal "#{@block.id}-1", @token.id
    assert_equal "#{@block.id}-1", @token.to_param
    assert_equal [ @block.id, 1 ], @token.to_key
  end

  test "dom ids stay addressable, which is what makes a bookmark a link" do
    assert_equal "w_token_#{@block.id}_1", ActionView::RecordIdentifier.dom_id(@token, :w)
  end

  test "a word can be looked up again from its id" do
    found = Token.locate(Block.where(book_id: @fixture[:book].id), @token.id)

    assert_equal @token, found
    assert_equal "dijo", found.surface
  end

  test "looking up a malformed or missing word raises rather than returning nil" do
    scope = Block.where(book_id: @fixture[:book].id)

    assert_raises(ActiveRecord::RecordNotFound) { Token.locate(scope, "nonsense") }
    assert_raises(ActiveRecord::RecordNotFound) { Token.locate(scope, "#{@block.id}-99") }
  end

  test "a word finds the sentence it sits in" do
    assert_equal @fixture[:sentence], @token.sentence
  end

  test "grammar comes from the morphology recorded at ingest time" do
    assert_equal "verdad", @block.token_at(3).surface
    assert_equal "verb - preterite, 3rd person singular", @token.grammar_summary
    assert @token.inflected?, "dijo should read as inflected from decir"
  end

  test "the block exposes its words in reading order" do
    assert_equal %w[Ella dijo la verdad], @block.tokens.map(&:surface)
    assert_equal [ 0, 1, 2, 3 ], @block.tokens.map(&:position)
    assert_nil @block.token_at(99)
  end
end
