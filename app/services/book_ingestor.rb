require "open3"
require "tmpdir"

# Streams a book through the Python NLP pipeline and into the database.
#
# The Python side emits one JSON object per block, so neither process ever holds
# a whole novel in memory. Rows go in with insert_all in batches because a
# 300-page book is on the order of 150,000 tokens.
class BookIngestor
  BATCH_SIZE = 200

  class IngestError < StandardError; end

  def initialize(book)
    @book = book
    @lemma_ids = {}
    @image_ids = {}
    @block_position = 0
    @word_count = 0
  end

  def call
    book.update!(status: "processing", ingest_error: nil)
    reset_existing_content

    Dir.mktmpdir("lector-ingest") do |workspace|
      images_dir = File.join(workspace, "images")
      FileUtils.mkdir_p(images_dir)

      book.file.open do |pdf|
        stream(pdf.path, images_dir)
      end
    end

    book.update!(
      status: "ready",
      ingested_at: Time.current,
      block_count: block_position,
      word_count: word_count
    )
    book
  rescue StandardError => error
    book.update_columns(status: "failed", ingest_error: "#{error.class}: #{error.message}".truncate(1000))
    raise
  end

  private

  attr_reader :book, :block_position, :word_count

  # Re-ingesting a book replaces its content rather than appending to it.
  def reset_existing_content
    book.purge_content!
    book.book_images.destroy_all
  end

  def stream(pdf_path, images_dir)
    command = [
      python_bin,
      Rails.root.join("lib/nlp/ingest.py").to_s,
      pdf_path,
      "--images-dir", images_dir,
      "--model", spacy_model
    ]
    command += [ "--max-pages", max_pages.to_s ] if max_pages

    buffer = []

    Open3.popen3(*command) do |stdin, stdout, stderr, wait_thread|
      stdin.close

      # Drained on its own thread; a full stderr pipe would otherwise deadlock
      # the child process partway through a long book.
      errors = Thread.new { stderr.read }

      stdout.each_line do |line|
        payload = parse(line)
        next if payload.blank?

        case payload["type"]
        when "meta"
          apply_metadata(payload)
        when "block"
          buffer << assign_position(payload)
          if buffer.size >= BATCH_SIZE
            persist(buffer, images_dir)
            buffer = []
          end
        end
      end

      persist(buffer, images_dir) if buffer.any?

      status = wait_thread.value
      unless status.success?
        raise IngestError, "ingest.py exited #{status.exitstatus}: #{errors.value.to_s.lines.last(5).join.strip}"
      end
    end
  end

  def parse(line)
    JSON.parse(line)
  rescue JSON::ParserError
    # The pipeline is line-oriented; a stray non-JSON line should not abort a book.
    Rails.logger.warn("[ingest] skipped unparseable line for book #{book.id}")
    nil
  end

  def assign_position(payload)
    payload["position"] = @block_position
    @block_position += 1
    payload
  end

  def apply_metadata(payload)
    attributes = { page_count: payload["page_count"] }
    attributes[:title] = payload["title"] if book.title.blank? && payload["title"].present?
    attributes[:author] = payload["author"] if book.author.blank? && payload["author"].present?
    book.update!(attributes)
  end

  def persist(buffer, images_dir)
    return if buffer.empty?

    Book.transaction do
      resolve_lemmas(buffer)
      block_ids = insert_blocks(buffer, images_dir)
      sentence_ids = insert_sentences(buffer, block_ids)
      insert_tokens(buffer, block_ids, sentence_ids)
    end
  end

  def insert_blocks(buffer, images_dir)
    now = Time.current

    rows = buffer.map do |payload|
      {
        book_id: book.id,
        book_image_id: image_id_for(payload, images_dir),
        position: payload["position"],
        kind: payload["kind"],
        page_number: payload["page"],
        text: payload["text"],
        created_at: now,
        updated_at: now
      }
    end

    result = Block.insert_all(rows, returning: %i[id position])
    result.rows.to_h { |id, position| [ position, id ] }
  end

  def insert_sentences(buffer, block_ids)
    rows = buffer.flat_map do |payload|
      block_id = block_ids.fetch(payload["position"])
      Array(payload["sentences"]).map do |sentence|
        {
          book_id: book.id,
          block_id: block_id,
          position: sentence["position"],
          char_start: sentence["start"],
          char_end: sentence["end"],
          text: sentence["text"]
        }
      end
    end

    return {} if rows.empty?

    result = Sentence.insert_all(rows, returning: %i[id block_id position])
    result.rows.to_h { |id, block_id, position| [ [ block_id, position ], id ] }
  end

  def insert_tokens(buffer, block_ids, sentence_ids)
    rows = []

    buffer.each do |payload|
      block_id = block_ids.fetch(payload["position"])
      index = 0

      Array(payload["sentences"]).each do |sentence|
        sentence_id = sentence_ids.fetch([ block_id, sentence["position"] ])

        sentence["tokens"].each do |token|
          rows << {
            book_id: book.id,
            block_id: block_id,
            sentence_id: sentence_id,
            lemma_id: @lemma_ids[lemma_key(token)],
            position: index,
            char_start: token["start"],
            char_end: token["end"],
            surface: token["surface"],
            pos: token["pos"],
            morph: token["morph"] || {}
          }
          index += 1
        end
      end
    end

    return if rows.empty?

    Token.insert_all(rows)
    @word_count += rows.size
  end

  # Collects every distinct lemma in the batch, inserts the ones we have not seen
  # before, and caches their ids so tokens can reference them.
  def resolve_lemmas(buffer)
    keys = buffer.flat_map { |payload|
      Array(payload["sentences"]).flat_map { |sentence|
        sentence["tokens"].map { |token| lemma_key(token) }
      }
    }.uniq

    missing = keys.reject { |key| @lemma_ids.key?(key) }
    return if missing.empty?

    now = Time.current
    rows = missing.map do |(text, pos)|
      { text: text, pos: pos, language: book.language, created_at: now, updated_at: now }
    end

    Lemma.insert_all(rows, unique_by: %i[language text pos])

    # Fetched by text alone rather than by (text, pos) pairs: it is a simpler
    # query, and caching the other parts of speech for a word we just saw tends
    # to save a lookup later anyway.
    Lemma.where(language: book.language, text: missing.map(&:first).uniq)
         .pluck(:text, :pos, :id)
         .each { |text, pos, id| @lemma_ids[[ text, pos ]] = id }
  end

  # A learner thinks of "haber" as one word whether it acts as a main verb or an
  # auxiliary, so those collapse into a single lemma.
  def lemma_key(token)
    pos = token["pos"] == "AUX" ? "VERB" : token["pos"]
    [ token["lemma"], pos ]
  end

  def image_id_for(payload, images_dir)
    image = payload["image"]
    return nil if image.blank?

    checksum = image["checksum"]
    @image_ids[checksum] ||= create_image(image, images_dir)
  end

  def create_image(image, images_dir)
    record = book.book_images.create!(
      checksum: image["checksum"],
      width: image["width"],
      height: image["height"]
    )

    path = File.join(images_dir, image["file"])
    if File.exist?(path)
      record.file.attach(
        io: File.open(path),
        filename: image["file"],
        content_type: Marcel::MimeType.for(Pathname.new(path))
      )
    end

    record.id
  end

  def python_bin
    return ENV["PYTHON_BIN"] if ENV["PYTHON_BIN"].present?

    venv = Rails.root.join(".venv/bin/python")
    File.executable?(venv) ? venv.to_s : "python3"
  end

  def spacy_model
    ENV.fetch("SPACY_MODEL", "es_core_news_md")
  end

  def max_pages
    ENV["INGEST_MAX_PAGES"].presence
  end
end
