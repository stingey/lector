# Turns a book already sitting in a development database into the sample that ships
# with the repo. Run once by a maintainer; the output is committed.
#
#   bin/rails demo:export BOOK=3 BLOCKS=2000
#
# Lemma ids are database-local, so words cannot carry them across. They are rewritten
# as indexes into a table of [text, pos] pairs that the installer resolves against
# whatever lemma rows the target database happens to have.
namespace :demo do
  desc "Export a book's first BLOCKS blocks as the bundled sample"
  task export: :environment do
    exporter = DemoBookExporter.new(
      book: Book.find(ENV.fetch("BOOK")),
      limit: Integer(ENV.fetch("BLOCKS", "2000"))
    )

    puts exporter.call
  end
end

class DemoBookExporter
  def initialize(book:, limit:)
    @book = book
    @limit = limit
  end

  def call
    blocks = book.blocks.in_order.limit(limit).includes(:sentences).to_a
    raise "book #{book.id} has no blocks" if blocks.empty?

    lemmas = lemma_table(blocks)
    indexes = lemmas.keys.each_with_index.to_h
    images = export_images(blocks)

    payload = {
      "title" => book.title,
      "language" => book.language,
      "page_count" => blocks.filter_map(&:page_number).max,
      "lemmas" => lemmas.values,
      "images" => images.values,
      "blocks" => blocks.map { |block| export_block(block, indexes, images) }
    }

    json = JSON.generate(payload)
    DemoBook::DEFAULT_PATH.dirname.mkpath
    DemoBook::DEFAULT_PATH.binwrite(ActiveSupport::Gzip.compress(json))

    summary(payload, json, images)
  end

  private

  attr_reader :book, :limit

  # Lemma id => [text, pos], in insertion order, so a word can name its lemma by the
  # position it takes in this list.
  def lemma_table(blocks)
    Lemma.where(id: blocks.flat_map(&:lemma_ids).uniq)
         .pluck(:id, :text, :pos)
         .to_h { |id, text, pos| [ id, [ text, pos ] ] }
  end

  def export_block(block, indexes, images)
    row = {
      "position" => block.position,
      "kind" => block.kind,
      "page" => block.page_number,
      "text" => block.text,
      "words" => export_words(block, indexes),
      "sentences" => block.sentences.map { |sentence|
        {
          "position" => sentence.position,
          "start" => sentence.char_start,
          "end" => sentence.char_end,
          "text" => sentence.text
        }
      }
    }

    row["image"] = images.fetch(block.book_image_id)["path"] if block.book_image_id
    row
  end

  def export_words(block, indexes)
    block.words.map do |word|
      entry = word.dup
      # Rewritten in place: "l" means "index into the lemma table" from here on.
      entry["l"] = indexes.fetch(word["l"]) if word["l"].present?
      entry
    end
  end

  # Copies each illustration into app/assets/images/demo, where Propshaft will
  # fingerprint and serve it like any other asset.
  def export_images(blocks)
    directory = Rails.root.join("app/assets/images", DemoBook::IMAGE_PREFIX)
    FileUtils.rm_rf(directory)
    directory.mkpath

    ids = blocks.filter_map(&:book_image_id).uniq
    records = BookImage.where(id: ids).includes(file_attachment: :blob).index_by(&:id)

    ids.each_with_index.to_h do |id, index|
      image = records.fetch(id)
      name = format("%04d%s", index, extension_for(image))
      image.file.open { |file| FileUtils.cp(file.path, directory.join(name)) }

      [ id, {
        "path" => File.join(DemoBook::IMAGE_PREFIX, name),
        "checksum" => image.checksum,
        "width" => image.width,
        "height" => image.height
      } ]
    end
  end

  def extension_for(image)
    case image.file.content_type
    when "image/png" then ".png"
    when "image/jpeg" then ".jpg"
    else File.extname(image.file.filename.to_s).presence || ".bin"
    end
  end

  def summary(payload, json, images)
    words = payload["blocks"].sum { |block| block["words"].size }

    [
      "#{payload["blocks"].size} blocks, #{words} words, " \
      "#{payload["lemmas"].size} lemmas, #{images.size} images",
      "#{DemoBook::DEFAULT_PATH.relative_path_from(Rails.root)} " \
      "#{(DemoBook::DEFAULT_PATH.size / 1024.0**2).round(2)} MB " \
      "(#{(json.bytesize / 1024.0**2).round(2)} MB uncompressed)"
    ].join("\n")
  end
end
