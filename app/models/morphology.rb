# Translates the Universal Dependencies feature tags that spaCy produces into
# plain English a learner can read.
#
# This is deliberately not an AI call. spaCy already resolved the grammar at
# ingest time, so describing it is a lookup table.
class Morphology
  PARTS_OF_SPEECH = {
    "NOUN" => "noun",
    "PROPN" => "proper noun",
    "VERB" => "verb",
    "AUX" => "auxiliary verb",
    "ADJ" => "adjective",
    "ADV" => "adverb",
    "PRON" => "pronoun",
    "DET" => "determiner",
    "ADP" => "preposition",
    "CCONJ" => "conjunction",
    "SCONJ" => "conjunction",
    "NUM" => "number",
    "INTJ" => "interjection",
    "PART" => "particle",
    "SYM" => "symbol",
    "X" => "other"
  }.freeze

  # Spanish tense names are a combination of Mood and Tense rather than either alone.
  TENSES = {
    [ "Ind", "Pres" ] => "present",
    [ "Ind", "Past" ] => "preterite",
    [ "Ind", "Imp" ] => "imperfect",
    [ "Ind", "Fut" ] => "future",
    [ "Ind", "Pqp" ] => "pluperfect",
    [ "Sub", "Pres" ] => "present subjunctive",
    [ "Sub", "Past" ] => "past subjunctive",
    [ "Sub", "Imp" ] => "imperfect subjunctive",
    [ "Sub", "Fut" ] => "future subjunctive",
    [ "Cnd", nil ] => "conditional",
    [ "Cnd", "Pres" ] => "conditional",
    [ "Imp", nil ] => "imperative",
    [ "Imp", "Pres" ] => "imperative"
  }.freeze

  PERSONS = { "1" => "1st person", "2" => "2nd person", "3" => "3rd person" }.freeze
  NUMBERS = { "Sing" => "singular", "Plur" => "plural" }.freeze
  GENDERS = { "Masc" => "masculine", "Fem" => "feminine" }.freeze

  VERB_FORMS = {
    "Inf" => "infinitive",
    "Part" => "past participle",
    "Ger" => "gerund"
  }.freeze

  attr_reader :pos, :features

  def initialize(pos:, features: {})
    @pos = pos.to_s
    @features = (features || {}).with_indifferent_access
  end

  def part_of_speech
    PARTS_OF_SPEECH.fetch(pos, pos.downcase.presence || "word")
  end

  # A short phrase such as "preterite, 3rd person singular" or "feminine plural".
  def description
    parts = verb? ? verb_parts : nominal_parts
    parts.compact.join(", ").presence
  end

  # "verb - preterite, 3rd person singular"
  def summary
    [ part_of_speech, description ].compact_blank.join(" - ")
  end

  def verb?
    pos == "VERB" || pos == "AUX"
  end

  private

  def verb_parts
    form = VERB_FORMS[features[:VerbForm]]
    return [ form ] if form && features[:Mood].blank?

    [ tense, person_and_number ]
  end

  def nominal_parts
    gendered = [ GENDERS[features[:Gender]], NUMBERS[features[:Number]] ].compact
    return [ gendered.join(" ") ] if gendered.any?

    [ VERB_FORMS[features[:VerbForm]] ]
  end

  def tense
    mood = features[:Mood]
    return nil if mood.blank?

    TENSES[[ mood, features[:Tense] ]] || TENSES[[ mood, nil ]]
  end

  def person_and_number
    [ PERSONS[features[:Person].to_s], NUMBERS[features[:Number]] ].compact.join(" ").presence
  end
end
