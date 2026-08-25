# Gives a new account something to read before it has uploaded anything.
#
# The sample's text and illustrations are committed to the repo, so a fresh deploy has
# a working book without object storage configured and without running the Python
# pipeline. Each reader gets their own copy: highlights, bookmarks and progress belong
# to one person, and a shared book would leak all three.
#
# Written by lib/tasks/demo.rake. Words in that file name their lemma by an index into
# a table of [text, pos] pairs rather than by id, because ids belong to the database
# they were written in.
class DemoBook
  DEFAULT_PATH = Rails.root.join("db/demo/content.json.gz")
  IMAGE_PREFIX = "demo".freeze
  BATCH_SIZE = 500

  class << self
    # Which bundle to install. Tests point this at a small one, or at nothing, so that
    # signing up does not mean writing a novel.
    attr_writer :path

    def path
      defined?(@path) ? @path : DEFAULT_PATH
    end

    def available?
      path.present? && path.exist?
    end

    # Returns the reader's copy, or nil when there is nothing bundled to install.
    # Installing twice is a no-op, so this is safe to call from seeds.
    def install_for(user)
      return nil unless available?

      existing = user.books.find_by(demo: true)
      return existing if existing

      new(user, content).call
    end

    # Held for the life of the process, since it is a few megabytes of parsed JSON that
    # every signup reads. Re-read when the file changes underneath it, which is what
    # makes a fresh export visible without a restart.
    def content
      key = [ path.to_s, path.mtime ]
      return @content if @content_key == key

      # Parsed before either is assigned, so a bad file leaves no stale bundle behind
      # under the new key.
      parsed = JSON.parse(ActiveSupport::Gzip.decompress(path.binread))
      @content_key = key
      @content = parsed
    end
  end

  def initialize(user, content)
    @user = user
    @content = content
  end

  # All or nothing: a partly installed book would look ready and read as gibberish.
  def call
    Book.transaction { install }
  end

  private

  attr_reader :user, :content

  def install
    book = create_book
    images = create_images(book)
    rollup = LemmaRollup.new

    blocks.each_slice(BATCH_SIZE) do |slice|
      # Resolved once and used twice: stored on the block, and counted into the rollup.
      # The bundled copy keeps its lemma indexes, so installing again still works.
      words = slice.to_h { |block| [ block.fetch("position"), localized_words(block) ] }

      block_ids = insert_blocks(book, slice, images, words)
      insert_sentences(book, slice, block_ids)

      slice.each do |block|
        position = block.fetch("position")
        rollup.add(block_ids.fetch(position), words.fetch(position))
      end
    end

    rollup.write!(book.id)
    book
  end

  def blocks
    content.fetch("blocks")
  end

  def language
    content.fetch("language", "es")
  end

  def create_book
    user.books.create!(
      title: content.fetch("title"),
      language: language,
      demo: true,
      status: "ready",
      ingested_at: Time.current,
      page_count: content["page_count"],
      block_count: blocks.size,
      word_count: blocks.sum { |block| block["words"].size }
    )
  end

  # Keyed by asset path, which is how a block refers to its illustration.
  def create_images(book)
    rows = content.fetch("images")
    return {} if rows.empty?

    now = Time.current
    result = BookImage.insert_all(
      rows.map { |image|
        {
          book_id: book.id,
          static_path: image.fetch("path"),
          checksum: image["checksum"],
          width: image["width"],
          height: image["height"],
          created_at: now,
          updated_at: now
        }
      },
      returning: %i[id static_path]
    )

    result.rows.to_h { |id, static_path| [ static_path, id ] }
  end

  def insert_blocks(book, slice, images, words)
    now = Time.current

    rows = slice.map do |block|
      {
        book_id: book.id,
        book_image_id: block["image"] && images[block["image"]],
        position: block.fetch("position"),
        kind: block.fetch("kind"),
        page_number: block["page"],
        text: block["text"],
        words: words.fetch(block.fetch("position")),
        created_at: now,
        updated_at: now
      }
    end

    result = Block.insert_all(rows, returning: %i[id position])
    result.rows.to_h { |id, position| [ position, id ] }
  end

  def insert_sentences(book, slice, block_ids)
    rows = slice.flat_map do |block|
      block_id = block_ids.fetch(block.fetch("position"))

      Array(block["sentences"]).map do |sentence|
        {
          book_id: book.id,
          block_id: block_id,
          position: sentence.fetch("position"),
          char_start: sentence["start"],
          char_end: sentence["end"],
          text: sentence["text"]
        }
      end
    end

    Sentence.insert_all(rows) if rows.any?
  end

  # Swaps each word's lemma index for the id that lemma has in this database.
  def localized_words(block)
    block.fetch("words").map do |word|
      index = word["l"]
      next word if index.nil?

      word.merge("l" => lemma_ids.fetch(index))
    end
  end

  # Every lemma the sample uses, resolved in one pass and shared with whatever the
  # reader's own books have already created. Indexed the way the export numbered them.
  def lemma_ids
    @lemma_ids ||= resolve_lemmas
  end

  def resolve_lemmas
    pairs = content.fetch("lemmas")
    return [] if pairs.empty?

    now = Time.current
    Lemma.insert_all(
      pairs.map { |text, pos| { text: text, pos: pos, language: language, created_at: now, updated_at: now } },
      unique_by: %i[language text pos]
    )

    # Fetched by text alone, the same way the ingester does: a simpler query, and the
    # other parts of speech for a word tend to be wanted anyway.
    existing = Lemma.where(language: language, text: pairs.map(&:first).uniq)
                    .pluck(:text, :pos, :id)
                    .to_h { |text, pos, id| [ [ text, pos ], id ] }

    pairs.map { |pair| existing.fetch(pair) }
  end
end
