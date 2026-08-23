class Token < ApplicationRecord
  belongs_to :book
  belongs_to :block
  belongs_to :sentence
  belongs_to :lemma, optional: true

  # Everything a hover tooltip shows, derived from data computed at ingest time.
  # No network call and no model inference happens here.
  def morphology
    @morphology ||= Morphology.new(pos: pos, features: morph)
  end

  # The reader selects lemmas.text alongside tokens so rendering a page of prose
  # does not issue a query per word.
  def lemma_text
    return self[:lemma_text] if has_attribute?(:lemma_text)

    lemma&.text
  end

  def grammar_summary
    morphology.summary
  end

  def inflected?
    lemma_text.present? && lemma_text.casecmp(surface).to_i != 0
  end

  def context_sentence
    sentence
  end
end
