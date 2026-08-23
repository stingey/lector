require "test_helper"

class BlockTest < ActiveSupport::TestCase
  setup do
    @fixture = build_annotated_book(users(:one))
    @block = @fixture[:block]
  end

  test "a block carries one word entry per word, in reading order" do
    assert_equal %w[Ella dijo la verdad], @block.words.map { |word| word["w"] }
    assert_equal [ 0, 1, 2, 3 ], @block.words.map { |word| word["p"] }
  end

  test "word offsets point at the characters the block text actually has" do
    @block.words.each do |word|
      assert_equal word["w"], @block.text[word["s"]...word["e"]],
                   "offsets for #{word["w"].inspect} do not line up with the block text"
    end
  end

  test "every word names the sentence it belongs to" do
    positions = @block.sentences.map(&:position)

    @block.words.each do |word|
      assert_includes positions, word["n"]
    end
  end
end
