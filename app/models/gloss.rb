# A cached contextual translation for one word form in one sentence.
#
# Keyed by lemma, surface form, and a digest of the sentence, so re-reading a
# passage or two readers hitting the same sentence costs nothing.
class Gloss < ApplicationRecord
  belongs_to :lemma

  validates :surface, :sentence_digest, presence: true

  def meaning
    payload["meaning"]
  end

  def dictionary
    payload["dictionary"]
  end

  def note
    payload["note"].presence
  end

  def literal
    payload["literal"].presence
  end
end
