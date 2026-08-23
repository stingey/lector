# One word occurrence in a book: a value read out of blocks.words, not a table row.
#
# A row per word cost 32 MB a novel and bought nothing the reader needed, because words
# are only ever fetched a block at a time. Anything that wants to count occurrences
# across a library reads book_lemmas instead.
#
# Identity is the pair (block, position): "<block_id>-<position>" in a URL and
# token_<block_id>_<position> as a DOM id, which is what keeps every word addressable
# and a bookmark a link you can follow.
class Token
  include ActiveModel::Conversion
  extend ActiveModel::Naming

  attr_reader :block, :position, :char_start, :char_end, :surface, :pos, :morph,
              :sentence_position, :lemma_id
  attr_writer :lemma_text

  def self.from_data(block, data)
    new(
      block: block,
      position: data["p"],
      char_start: data["s"],
      char_end: data["e"],
      surface: data["w"],
      sentence_position: data["n"].to_i,
      lemma_id: data["l"],
      pos: data["x"],
      morph: data["m"] || {}
    )
  end

  # Resolves "<block_id>-<position>" inside a scope of blocks the reader may see, so an
  # id from someone else's book is a 404 rather than a leak.
  def self.locate(blocks, id)
    block_id, position = id.to_s.split("-", 2)
    raise ActiveRecord::RecordNotFound, "malformed word id #{id.inspect}" if position.blank?

    block = blocks.find(block_id)
    block.token_at(position.to_i) ||
      raise(ActiveRecord::RecordNotFound, "block #{block_id} has no word at position #{position}")
  end

  def initialize(block:, position:, char_start:, char_end:, surface:,
                 sentence_position: 0, lemma_id: nil, pos: nil, morph: {})
    @block = block
    @position = position
    @char_start = char_start
    @char_end = char_end
    @surface = surface
    @sentence_position = sentence_position
    @lemma_id = lemma_id
    @pos = pos
    @morph = morph
  end

  def id
    "#{block.id}-#{position}"
  end
  alias to_param id

  # A two part key, so dom_id renders token_<block_id>_<position>.
  def to_key
    [ block.id, position ]
  end

  def persisted?
    true
  end

  def ==(other)
    other.is_a?(Token) && other.to_key == to_key
  end
  alias eql? ==

  def hash
    to_key.hash
  end

  def block_id
    block.id
  end

  def book_id
    block.book_id
  end

  # Sentences are still rows: the translator prompts with them, the gloss cache is keyed
  # on them, and a review records the one it quizzed.
  def sentence
    block.sentences.detect { |candidate| candidate.position == sentence_position }
  end
  alias context_sentence sentence

  # Set in bulk by the reader, which resolves every lemma on the page at once. Falls
  # back to its own lookup for a single word card.
  def lemma_text
    return @lemma_text if defined?(@lemma_text)

    @lemma_text = lemma_id.present? ? Lemma.where(id: lemma_id).pick(:text) : nil
  end

  # Everything a hover tooltip shows, derived from data computed at ingest time.
  # No network call and no model inference happens here.
  def morphology
    @morphology ||= Morphology.new(pos: pos, features: morph)
  end

  def grammar_summary
    morphology.summary
  end

  def inflected?
    lemma_text.present? && lemma_text.casecmp(surface).to_i != 0
  end
end
