# Contextual word lookup: the one place this app calls a language model.
#
# Grammar is not asked for. spaCy already resolved the lemma, part of speech, and
# morphology at ingest time, and those are passed into the prompt as facts. The
# model is left with the single job it is actually good at: saying what this word
# means in this sentence.
#
# Every result is cached by (lemma, surface form, sentence), so a given lookup is
# paid for once and then served from Postgres forever.
class Translator
  PROVIDERS = { "openai" => "Translator::OpenaiProvider", "anthropic" => "Translator::AnthropicProvider" }.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You help an English speaker read Spanish books. You are given a sentence and one
    target word from it, along with grammar that has already been determined. Explain
    what the target word means in this specific sentence.

    Reply with JSON only, no prose and no code fences:
    {"meaning": "...", "dictionary": "...", "literal": "", "note": ""}

    meaning:    what the word conveys here, in English. Under 60 characters, no trailing period.
    dictionary: the general meaning of the base form, in English. Under 60 characters.
    literal:    only when the word belongs to an idiom whose literal reading differs; otherwise "".
    note:       one short note only when genuinely useful to a learner (idiom, false friend,
                pronominal or reflexive use, regionalism, register). Under 140 characters; otherwise "".
  PROMPT

  class Error < StandardError; end

  def self.configured?
    provider.configured?
  rescue Error
    false
  end

  def self.provider
    name = ENV.fetch("TRANSLATOR_PROVIDER", "openai").downcase
    class_name = PROVIDERS[name] or raise Error, "Unknown TRANSLATOR_PROVIDER #{name.inspect}"
    class_name.constantize.new
  end

  def self.lookup(token)
    new.lookup(token)
  end

  # Returns a persisted Gloss, or nil when no provider is configured.
  def lookup(token)
    return nil if token.lemma_id.blank?

    sentence = token.sentence
    digest = sentence.digest

    cached = Gloss.find_by(lemma_id: token.lemma_id, surface: token.surface, sentence_digest: digest)
    return cached if cached

    return nil unless self.class.configured?

    provider = self.class.provider
    payload = provider.complete(system: SYSTEM_PROMPT, user: prompt_for(token, sentence))

    store(token, digest, normalize(payload), provider.model)
  end

  private

  def prompt_for(token, sentence)
    lines = [ %(Sentence: "#{sentence.text.strip}"), %(Target word: "#{token.surface}") ]
    lines << "Base form: #{token.lemma_text}" if token.lemma_text.present?

    grammar = token.morphology.summary
    lines << "Grammar (already determined, do not contradict): #{grammar}" if grammar.present?

    lines.join("\n")
  end

  def normalize(payload)
    {
      "meaning" => squish(payload["meaning"]),
      "dictionary" => squish(payload["dictionary"]),
      "literal" => squish(payload["literal"]),
      "note" => squish(payload["note"])
    }
  end

  def squish(value)
    value.to_s.strip.squeeze(" ").presence
  end

  def store(token, digest, payload, model)
    Gloss.create!(
      lemma_id: token.lemma_id,
      surface: token.surface,
      sentence_digest: digest,
      payload: payload,
      model: model
    )
  rescue ActiveRecord::RecordNotUnique
    # Two readers hit the same sentence at once; whichever landed first is fine.
    Gloss.find_by!(lemma_id: token.lemma_id, surface: token.surface, sentence_digest: digest)
  end
end
