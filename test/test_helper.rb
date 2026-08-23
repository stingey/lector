ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)

    fixtures :all
  end
end

module SignInHelper
  def sign_in(user, password: "password")
    post session_path, params: { email_address: user.email_address, password: password }
  end
end

# Builds a small annotated book directly, standing in for the Python pipeline so tests
# do not need spaCy installed.
#
# Note the punctuation: only words get entries, so the final period exercises the
# renderer's handling of the gaps between them.
module BookBuilder
  WORDS = [
    { surface: "Ella", lemma: "ella", pos: "PRON", morph: { "Gender" => "Fem", "Number" => "Sing", "Person" => "3" } },
    { surface: "dijo", lemma: "decir", pos: "VERB", morph: { "Mood" => "Ind", "Number" => "Sing", "Person" => "3", "Tense" => "Past", "VerbForm" => "Fin" } },
    { surface: "la", lemma: "el", pos: "DET", morph: { "Gender" => "Fem", "Number" => "Sing" } },
    { surface: "verdad", lemma: "verdad", pos: "NOUN", morph: { "Gender" => "Fem", "Number" => "Sing" } }
  ].freeze

  def build_annotated_book(user, title: "Prueba")
    book = user.books.create!(title: title, status: "ready", page_count: 1, block_count: 1)
    built = build_block_with_words(book, position: 0, text: "Ella dijo la verdad.", words: WORDS)

    book.update!(word_count: built[:tokens].size)
    verb = built[:tokens].find { |token| token.surface == "dijo" }

    { book: book, block: built[:block], sentence: built[:sentence],
      tokens: built[:tokens], token: verb, lemma: Lemma.find(verb.lemma_id) }
  end

  # One paragraph, its sentence, its inline words, and the lemma rollup they imply.
  # Each word needs a :surface and may carry :lemma, :pos and :morph.
  def build_block_with_words(book, position:, text:, words:, page_number: nil)
    block = book.blocks.create!(position: position, kind: "paragraph",
                                page_number: page_number || position + 1, text: text)
    sentence = book.sentences.create!(block: block, position: 0, char_start: 0,
                                      char_end: text.length, text: text)

    cursor = 0

    entries = words.each_with_index.map do |word, index|
      # Scanned forward from the previous word so a short one like "la" is not matched
      # inside an earlier one ("Ella").
      offset = text.index(word[:surface], cursor)
      raise ArgumentError, "#{word[:surface].inspect} is not in #{text.inspect}" if offset.nil?

      cursor = offset + word[:surface].length

      entry = { "p" => index, "s" => offset, "e" => cursor, "w" => word[:surface], "n" => 0 }
      entry["x"] = word[:pos] if word[:pos]
      entry["m"] = word[:morph] if word[:morph]

      if word[:lemma]
        lemma = Lemma.find_or_create_by!(text: word[:lemma], pos: word[:pos] || "NOUN", language: "es")
        entry["l"] = lemma.id
      end

      entry
    end

    block.update!(words: entries)
    record_lemma_stats(book, block)

    { block: block, sentence: sentence, tokens: block.tokens }
  end

  private

  # The same rollup the ingester writes, so tests exercise the aggregates the word bank
  # actually reads.
  def record_lemma_stats(book, block)
    block.tokens.group_by(&:lemma_id).each do |lemma_id, group|
      next if lemma_id.blank?

      rollup = BookLemma.find_or_initialize_by(book_id: book.id, lemma_id: lemma_id)
      rollup.count += group.size
      rollup.surfaces = group.each_with_object(rollup.surfaces.dup) { |token, totals|
        totals[token.surface] = totals.fetch(token.surface, 0) + 1
      }
      rollup.sample_block_id ||= block.id
      rollup.sample_word_position ||= group.first.position
      rollup.save!
    end
  end
end

class ActionDispatch::IntegrationTest
  include SignInHelper
  include BookBuilder
end

class ActiveSupport::TestCase
  include BookBuilder
end
