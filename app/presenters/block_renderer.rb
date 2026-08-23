# Rebuilds a paragraph as HTML with every word wrapped in its own span.
#
# Token offsets are relative to the block's own text, so walking them in order
# and emitting the untouched gaps in between reproduces the original punctuation
# and spacing exactly. Nothing is reconstructed or guessed.
class BlockRenderer
  include ActionView::Helpers::OutputSafetyHelper
  include ActionView::RecordIdentifier

  # Lemma ids the reader has saved, mapped to their study status, so a saved word
  # highlights in every one of its conjugations.
  #
  # Bookmarked token ids are separate from that: a bookmark marks one occurrence of
  # one word, because it stands for a place in the book rather than for vocabulary.
  def initialize(block, tokens:, statuses_by_lemma: {}, bookmarked_token_ids: [])
    @block = block
    @tokens = tokens
    @statuses_by_lemma = statuses_by_lemma
    @bookmarked_token_ids = bookmarked_token_ids.to_set
  end

  def to_html
    return "".html_safe if text.blank?

    output = +""
    cursor = 0

    tokens.each do |token|
      next if token.char_start < cursor # defensive: overlapping spans would corrupt output

      output << escape(text[cursor...token.char_start]) if token.char_start > cursor
      output << word_span(token)
      cursor = token.char_end
    end

    output << escape(text[cursor..]) if cursor < text.length
    output.html_safe
  end

  private

  attr_reader :block, :tokens, :statuses_by_lemma, :bookmarked_token_ids

  def text
    @text ||= block.text.to_s
  end

  def word_span(token)
    surface = text[token.char_start...token.char_end]
    status = statuses_by_lemma[token.lemma_id]

    classes = [ "w" ]
    classes << "w--#{status}" if status
    classes << "w--bookmarked" if bookmarked_token_ids.include?(token.id)

    attributes = {
      # Every word is addressable, which is what makes a bookmark a link you can
      # follow rather than just a page number.
      id: dom_id(token, :w),
      class: classes.join(" "),
      "data-token-id" => token.id,
      "data-lemma-id" => token.lemma_id,
      "data-lemma" => token.lemma_text,
      "data-grammar" => token.grammar_summary
    }

    tag = +"<span"
    attributes.each { |name, value| tag << %( #{name}="#{escape(value)}") if value.present? }
    tag << ">" << escape(surface) << "</span>"
    tag
  end

  def escape(value)
    ERB::Util.html_escape(value.to_s)
  end
end
