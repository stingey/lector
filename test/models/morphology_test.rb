require "test_helper"

class MorphologyTest < ActiveSupport::TestCase
  test "describes Spanish tenses as a learner would name them" do
    assert_equal "verb - preterite, 3rd person singular",
                 summary("VERB", Mood: "Ind", Tense: "Past", Person: "3", Number: "Sing")

    assert_equal "verb - imperfect, 1st person plural",
                 summary("VERB", Mood: "Ind", Tense: "Imp", Person: "1", Number: "Plur")

    assert_equal "verb - present subjunctive, 2nd person singular",
                 summary("VERB", Mood: "Sub", Tense: "Pres", Person: "2", Number: "Sing")

    assert_equal "verb - conditional, 3rd person singular",
                 summary("VERB", Mood: "Cnd", Person: "3", Number: "Sing")
  end

  test "describes non-finite verb forms" do
    assert_equal "verb - infinitive", summary("VERB", VerbForm: "Inf")
    assert_equal "verb - gerund", summary("VERB", VerbForm: "Ger")
  end

  test "describes gender and number for nouns and adjectives" do
    assert_equal "noun - masculine singular", summary("NOUN", Gender: "Masc", Number: "Sing")
    assert_equal "adjective - feminine plural", summary("ADJ", Gender: "Fem", Number: "Plur")
  end

  test "falls back to the part of speech alone when there are no features" do
    assert_equal "preposition", summary("ADP")
    assert_equal "adverb", summary("ADV")
  end

  private

  def summary(pos, **features)
    Morphology.new(pos: pos, features: features.transform_keys(&:to_s)).summary
  end
end
