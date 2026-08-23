# How one lemma behaves in one book: how often it occurs, in which surface forms, and
# one place it happens.
#
# Written at ingest time, because once the words stop being rows there is nothing left
# to group by. Sized to a reader's vocabulary rather than to the length of their books:
# a novel is about 12,000 rows here against 158,000 words.
class BookLemma < ApplicationRecord
  belongs_to :book
  belongs_to :lemma

  scope :for_books, ->(books) { where(book_id: books) }

  # The occurrence held up as an example in the quiz.
  def sample_token
    return nil if sample_block_id.blank?

    Block.find_by(id: sample_block_id)&.token_at(sample_word_position)
  end

  # Surface forms across several books of the same reader, merged and ranked.
  def self.merged_surfaces(rows, limit: 12)
    rows.pluck(:surfaces)
        .each_with_object(Hash.new(0)) { |surfaces, totals|
          surfaces.each { |surface, uses| totals[surface] += uses }
        }
        .sort_by { |_, uses| -uses }
        .first(limit)
        .to_h
  end
end
