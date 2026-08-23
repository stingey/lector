module WordsHelper
  PART_OF_SPEECH_FILTERS = %w[VERB NOUN ADJ ADV PRON PROPN ADP CCONJ DET].freeze

  SORT_LABELS = {
    "added" => "Recently added",
    "alphabetical" => "A to Z",
    "due" => "Due soonest",
    "recent_review" => "Recently reviewed"
  }.freeze

  def part_of_speech_options
    PART_OF_SPEECH_FILTERS.map { |pos| [ Morphology::PARTS_OF_SPEECH.fetch(pos, pos).capitalize, pos ] }
  end

  def sort_options
    SORT_LABELS.map { |value, label| [ label, value ] }
  end

  # Deep link back to the exact word in the reader where this entry was saved.
  def source_reader_path(entry)
    token = entry.source_token
    block = token&.block
    return nil if block.blank?

    book = entry.source_book || block.book
    read_book_path(book,
                   page: book.page_for_block_position(block.position),
                   anchor: dom_id(token, :w))
  end
end
