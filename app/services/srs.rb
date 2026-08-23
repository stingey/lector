require "fsrs_ruby"

# Spaced repetition scheduling, wrapping the FSRS-6 algorithm.
#
# FSRS decides when a word should come back by tracking two numbers per word:
# stability (how durably it is remembered) and difficulty (how hard it is for this
# reader). Grading a card updates both and produces the next due date, which is
# why a review session stays small no matter how large the word bank grows.
class Srs
  STATES = {
    FsrsRuby::State::NEW => "new",
    FsrsRuby::State::LEARNING => "learning",
    FsrsRuby::State::REVIEW => "review",
    FsrsRuby::State::RELEARNING => "relearning"
  }.freeze

  STATE_VALUES = STATES.invert.freeze

  RATINGS = {
    "again" => FsrsRuby::Rating::AGAIN,
    "hard" => FsrsRuby::Rating::HARD,
    "good" => FsrsRuby::Rating::GOOD,
    "easy" => FsrsRuby::Rating::EASY
  }.freeze

  def self.rating_for(name)
    RATINGS[name.to_s]
  end

  # Grades a card and writes back both the new schedule and a review log row.
  def self.grade!(entry, rating:, sentence: nil, now: Time.current)
    new.grade!(entry, rating: rating, sentence: sentence, now: now)
  end

  # What each button would do, so the UI can show real intervals before committing.
  def self.preview(entry, now: Time.current)
    new.preview(entry, now: now)
  end

  def initialize(scheduler: nil)
    @scheduler = scheduler || FsrsRuby.new(
      request_retention: 0.9,
      enable_short_term: true,
      learning_steps: [ "1m", "10m" ],
      relearning_steps: [ "10m" ],
      enable_fuzz: true
    )
  end

  def grade!(entry, rating:, sentence: nil, now: Time.current)
    value = rating.is_a?(Integer) ? rating : self.class.rating_for(rating)
    raise ArgumentError, "unknown rating #{rating.inspect}" if value.blank?

    state_before = entry.fsrs_state
    result = scheduler.next(card_for(entry, now), now, value)
    card = result.card

    ActiveRecord::Base.transaction do
      apply(entry, card, now)
      entry.lapses = card.lapses
      entry.save!

      entry.reviews.create!(
        rating: value,
        sentence: sentence,
        state_before: state_before,
        stability_after: card.stability,
        difficulty_after: card.difficulty,
        elapsed_days: card.elapsed_days,
        scheduled_days: card.scheduled_days,
        reviewed_at: now
      )
    end

    entry
  end

  def preview(entry, now: Time.current)
    card = card_for(entry, now)

    RATINGS.transform_values do |value|
      scheduler.next(card.dup, now, value).card.due
    end
  end

  private

  attr_reader :scheduler

  def card_for(entry, now)
    return FsrsRuby.create_empty_card(now) if entry.due_at.blank?

    FsrsRuby::Card.new(
      due: entry.due_at,
      stability: entry.stability.to_f,
      difficulty: entry.difficulty.to_f,
      scheduled_days: entry.scheduled_days.to_f,
      learning_steps: entry.learning_steps.to_i,
      reps: entry.reps.to_i,
      lapses: entry.lapses.to_i,
      state: STATE_VALUES.fetch(entry.fsrs_state, FsrsRuby::State::NEW),
      last_review: entry.last_reviewed_at
    )
  end

  def apply(entry, card, now)
    entry.stability = card.stability
    entry.difficulty = card.difficulty
    entry.due_at = card.due
    entry.scheduled_days = card.scheduled_days.to_f
    entry.learning_steps = card.learning_steps.to_i
    entry.reps = card.reps
    entry.fsrs_state = STATES.fetch(card.state, "learning")
    entry.last_reviewed_at = now
  end
end
