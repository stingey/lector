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

# Builds a small annotated book directly, standing in for the Python pipeline so
# tests do not need spaCy installed.
#
# Note the punctuation: only word tokens get rows, so the final period exercises
# the renderer's handling of the gaps between tokens.
module BookBuilder
  WORDS = [
    { surface: "Ella", lemma: "ella", pos: "PRON", morph: { "Gender" => "Fem", "Number" => "Sing", "Person" => "3" } },
    { surface: "dijo", lemma: "decir", pos: "VERB", morph: { "Mood" => "Ind", "Number" => "Sing", "Person" => "3", "Tense" => "Past", "VerbForm" => "Fin" } },
    { surface: "la", lemma: "el", pos: "DET", morph: { "Gender" => "Fem", "Number" => "Sing" } },
    { surface: "verdad", lemma: "verdad", pos: "NOUN", morph: { "Gender" => "Fem", "Number" => "Sing" } }
  ].freeze

  def build_annotated_book(user, title: "Prueba")
    text = "Ella dijo la verdad."
    book = user.books.create!(title: title, status: "ready", page_count: 1, block_count: 1)
    block = book.blocks.create!(position: 0, kind: "paragraph", page_number: 1, text: text)
    sentence = book.sentences.create!(block: block, position: 0, char_start: 0, char_end: text.length, text: text)

    cursor = 0

    tokens = WORDS.each_with_index.map do |word, index|
      # Scanned forward from the previous token so a short word like "la" is not
      # matched inside an earlier one ("Ella").
      offset = text.index(word[:surface], cursor)
      cursor = offset + word[:surface].length

      book.tokens.create!(
        block: block,
        sentence: sentence,
        lemma: Lemma.find_or_create_by!(text: word[:lemma], pos: word[:pos], language: "es"),
        position: index,
        char_start: offset,
        char_end: offset + word[:surface].length,
        surface: word[:surface],
        pos: word[:pos],
        morph: word[:morph]
      )
    end

    book.update!(word_count: tokens.size)
    verb = tokens.find { |token| token.surface == "dijo" }

    { book: book, block: block, sentence: sentence, tokens: tokens, token: verb, lemma: verb.lemma }
  end
end

class ActionDispatch::IntegrationTest
  include SignInHelper
  include BookBuilder
end

class ActiveSupport::TestCase
  include BookBuilder
end
