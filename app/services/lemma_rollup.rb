# Counts how each lemma behaves in one book, on the way to the book_lemmas rows the
# word bank and quiz read.
#
# Words live inside blocks rather than in rows of their own, so nothing can group by
# them after the fact: whoever writes a book's words has to count them at the same
# time. Both producers do it through here so the aggregates cannot drift apart.
#
# Only a few thousand lemmas make up a novel, so the tally stays small enough to hold
# in memory for the length of an ingest even though the words themselves stream past.
class LemmaRollup
  def initialize
    @stats = {}
  end

  # Words are the entries stored in blocks.words: "l" lemma id, "w" surface, "p"
  # position. Words with no lemma are skipped, since there is nothing to study.
  def add(block_id, words)
    Array(words).each do |word|
      lemma_id = word["l"]
      next if lemma_id.blank?

      stat = (@stats[lemma_id] ||= {
        count: 0,
        surfaces: Hash.new(0),
        sample_block_id: block_id,
        sample_word_position: word["p"]
      })

      stat[:count] += 1
      stat[:surfaces][word["w"]] += 1
    end

    self
  end

  def empty?
    @stats.empty?
  end

  def write!(book_id)
    return 0 if empty?

    now = Time.current
    rows = @stats.map { |lemma_id, stat|
      {
        book_id: book_id,
        lemma_id: lemma_id,
        count: stat[:count],
        surfaces: stat[:surfaces],
        sample_block_id: stat[:sample_block_id],
        sample_word_position: stat[:sample_word_position],
        created_at: now,
        updated_at: now
      }
    }

    rows.each_slice(1000) { |slice| BookLemma.insert_all(slice, unique_by: %i[book_id lemma_id]) }
    rows.size
  end
end
