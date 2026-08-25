require "test_helper"

class DemoBookTest < ActiveSupport::TestCase
  setup { @user = users(:two) }

  test "installing gives the reader their own readable copy" do
    with_bundled_sample do
      book = DemoBook.install_for(@user)

      assert_equal @user, book.user
      assert book.demo?
      assert book.ready?
      assert_equal "Libro de muestra", book.title
      assert_equal 2, book.block_count
      assert_equal 2, book.word_count
    end
  end

  test "words arrive with the lemma ids of this database rather than the exported ones" do
    with_bundled_sample do
      book = DemoBook.install_for(@user)
      token = book.blocks.in_order.first.tokens.first

      assert_equal "gato", token.surface
      assert_equal "gato", token.lemma_text
      assert_equal "NOUN", token.pos
      assert_equal "El gato duerme.", token.sentence.text
    end
  end

  test "an existing lemma is reused rather than duplicated" do
    existing = Lemma.create!(text: "gato", pos: "NOUN", language: "es")

    with_bundled_sample do
      book = DemoBook.install_for(@user)

      assert_equal existing.id, book.blocks.in_order.first.tokens.first.lemma_id
      assert_equal 1, Lemma.where(text: "gato", pos: "NOUN", language: "es").count
    end
  end

  test "the lemma rollup counts every word, so the word bank can read it" do
    with_bundled_sample do
      book = DemoBook.install_for(@user)
      rollup = BookLemma.where(book: book)

      assert_equal 2, rollup.count
      assert_equal book.word_count, rollup.sum(:count)
      assert_equal({ "duerme" => 1 }, rollup.find_by(lemma: Lemma.find_by(text: "dormir")).surfaces)
      assert_equal "gato", rollup.find_by(lemma: Lemma.find_by(text: "gato")).sample_token.surface
    end
  end

  test "illustrations point at committed assets rather than at object storage" do
    with_bundled_sample do
      book = DemoBook.install_for(@user)
      image = book.book_images.sole

      assert_equal "demo/0000.jpg", image.source
      assert_not image.file.attached?
      assert_equal image, book.blocks.in_order.last.book_image
    end
  end

  test "installing twice hands back the same copy" do
    with_bundled_sample do
      first = DemoBook.install_for(@user)

      assert_no_difference -> { Block.count } do
        assert_equal first.id, DemoBook.install_for(@user).id
      end
    end
  end

  test "two readers get separate copies of the same sample" do
    with_bundled_sample do
      mine = DemoBook.install_for(@user)
      yours = DemoBook.install_for(users(:one))

      assert_not_equal mine.id, yours.id
      assert_equal mine.title, yours.title
    end
  end

  test "nothing is installed when no sample is bundled" do
    DemoBook.path = nil

    assert_nil DemoBook.install_for(@user)
  end

  test "a failed install leaves no half a book behind" do
    broken = BundledSampleHelper::SAMPLE.deep_dup
    broken["blocks"].first["words"].first["l"] = 99 # a lemma the export never listed

    with_bundled_sample(broken) do
      assert_no_difference [ -> { Book.count }, -> { Block.count }, -> { BookImage.count } ] do
        assert_raises(IndexError) { DemoBook.install_for(@user) }
      end
    end
  end

  # The file that actually ships. Slower than the rest, and the only check that the
  # committed export is still loadable and self consistent.
  test "the bundled sample installs and reads end to end" do
    skip "no bundled sample in this checkout" unless DemoBook::DEFAULT_PATH.exist?

    DemoBook.path = DemoBook::DEFAULT_PATH
    book = DemoBook.install_for(@user)

    assert book.ready?
    assert_operator book.block_count, :>, 0
    assert_equal book.word_count, BookLemma.where(book: book).sum(:count)
    assert_equal book.block_count, book.blocks.count

    book.book_images.each do |image|
      assert Rails.root.join("app/assets/images", image.static_path).exist?,
             "#{image.static_path} is referenced by the sample but not committed"
    end

    words = book.blocks.in_order.first(50).flat_map(&:tokens)
    assert words.any?, "the opening pages should carry words"
    assert words.all? { |token| token.surface.present? }
    assert words.select(&:lemma_id).all? { |token| token.lemma_text.present? },
           "every lemma id in the sample should resolve to a lemma row"
  ensure
    DemoBook.path = nil
  end
end
