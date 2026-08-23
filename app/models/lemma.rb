class Lemma < ApplicationRecord
  has_many :book_lemmas, dependent: :delete_all
  has_many :vocab_entries, dependent: :destroy
  has_many :glosses, dependent: :destroy

  validates :text, :pos, presence: true

  scope :for_language, ->(language) { where(language: language) }

  def part_of_speech
    Morphology::PARTS_OF_SPEECH.fetch(pos, pos.to_s.downcase)
  end

  # Verbs are displayed by their infinitive, which is what the lemma already is.
  def display_text
    text
  end

  def to_s
    text
  end
end
