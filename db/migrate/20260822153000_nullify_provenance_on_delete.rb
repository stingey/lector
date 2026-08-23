# A saved word is worth more than the book it came from, so removing a book must not
# take the word bank with it. These three references only record provenance -- where a
# word was found and which sentence a review used -- so they nullify on delete.
class NullifyProvenanceOnDelete < ActiveRecord::Migration[8.0]
  REFERENCES = [
    { table: :vocab_entries, to: :books, column: :source_book_id },
    { table: :vocab_entries, to: :tokens, column: :source_token_id },
    { table: :reviews, to: :sentences, column: :sentence_id }
  ].freeze

  def up
    REFERENCES.each do |ref|
      remove_foreign_key ref[:table], column: ref[:column]
      add_foreign_key ref[:table], ref[:to], column: ref[:column], on_delete: :nullify
    end
  end

  def down
    REFERENCES.each do |ref|
      remove_foreign_key ref[:table], column: ref[:column]
      add_foreign_key ref[:table], ref[:to], column: ref[:column]
    end
  end
end
