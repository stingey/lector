require "csv"

# Imports an existing deck into the word bank.
#
# Written against the shape langflash stores cards in (spanish_text, english_text,
# part_of_speech), which is why the schema keeps gloss as free text rather than
# something derived: an imported card carries a meaning the reader already wrote.
#
# Export from langflash with:
#   rails runner 'puts Card.all.map { |c| [c.spanish_text, c.english_text, c.part_of_speech].to_csv }.join'
class LangflashImporter
  PART_OF_SPEECH = { "noun" => "NOUN", "verb" => "VERB" }.freeze

  Result = Struct.new(:imported, :skipped, :unmatched, keyword_init: true)

  def initialize(user, language: "es")
    @user = user
    @language = language
  end

  def import_csv(path)
    rows = CSV.read(path, headers: false).map { |spanish, english, pos| { spanish: spanish, english: english, pos: pos } }
    import(rows)
  end

  def import(rows)
    result = Result.new(imported: 0, skipped: 0, unmatched: [])

    rows.each do |row|
      spanish = row[:spanish].to_s.strip.downcase
      next if spanish.blank?

      lemma = find_lemma(spanish, row[:pos])

      if lemma.nil?
        result.unmatched << spanish
        next
      end

      entry = user.vocab_entries.find_or_initialize_by(lemma: lemma)

      if entry.persisted?
        result.skipped += 1
        next
      end

      entry.status = "learning"
      entry.gloss = row[:english].to_s.strip.presence
      entry.save!
      result.imported += 1
    end

    result
  end

  private

  attr_reader :user, :language

  # Prefers a lemma that already exists from a book the reader has ingested, since
  # that one will actually highlight while reading. Falls back to creating it.
  def find_lemma(text, part_of_speech)
    pos = PART_OF_SPEECH[part_of_speech.to_s.strip.downcase]

    scope = Lemma.for_language(language).where(text: text)
    return scope.find_by(pos: pos) || scope.first if pos.blank?

    scope.find_by(pos: pos) || Lemma.create!(text: text, pos: pos, language: language)
  end
end
