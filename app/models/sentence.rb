class Sentence < ApplicationRecord
  belongs_to :book
  belongs_to :block

  # The cache key for a contextual translation: the same word in the same
  # sentence should never be paid for twice.
  def digest
    Digest::SHA256.hexdigest(text.to_s.strip.squeeze(" "))
  end
end
