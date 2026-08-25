class Translator
  # Works with OpenAI and with anything that speaks its chat-completions dialect,
  # which includes Gemini's compatibility endpoint, Groq, and OpenRouter. Point
  # TRANSLATOR_BASE_URL at whichever one you want.
  class OpenaiProvider < BaseProvider
    DEFAULT_BASE_URL = "https://api.openai.com/v1".freeze
    DEFAULT_MODEL = "gpt-5.4-mini".freeze

    # Naming what a word means in one sentence needs no deliberation, and left to
    # their own devices the gpt-5 models spend six to ten seconds reasoning before
    # answering. Held to their lowest setting they answer in about two.
    #
    # The generations disagree about what that setting is called: gpt-5 and
    # gpt-5-mini accept "minimal" and reject "none", and gpt-5.4 does the reverse,
    # where "low" is the floor. Models outside the family reject the parameter
    # outright, so they never see it.
    REASONING_MODELS = /\Agpt-5/
    ORIGINAL_GPT5 = /\Agpt-5(-|\z)/

    def model
      ENV.fetch("TRANSLATOR_MODEL", DEFAULT_MODEL)
    end

    private

    def api_key
      ENV["TRANSLATOR_API_KEY"].presence || ENV["OPENAI_API_KEY"].presence
    end

    def endpoint
      base = ENV.fetch("TRANSLATOR_BASE_URL", DEFAULT_BASE_URL).chomp("/")
      "#{base}/chat/completions"
    end

    def headers
      { "Content-Type" => "application/json", "Authorization" => "Bearer #{api_key}" }
    end

    def body(system:, user:)
      payload = {
        model: model,
        messages: [
          { role: "system", content: system },
          { role: "user", content: user }
        ],
        response_format: { type: "json_object" }
      }

      effort = reasoning_effort
      payload[:reasoning_effort] = effort if effort.present?
      payload
    end

    # Set TRANSLATOR_REASONING_EFFORT to medium or high to trade latency back for
    # deliberation, or to an empty string to omit the parameter entirely.
    def reasoning_effort
      return nil if @omit_reasoning_effort
      return nil unless model.match?(REASONING_MODELS)

      ENV.fetch("TRANSLATOR_REASONING_EFFORT", default_reasoning_effort).presence
    end

    def default_reasoning_effort
      model.match?(ORIGINAL_GPT5) ? "minimal" : "low"
    end

    # A newer model may rename the setting again, and a rejected value would
    # otherwise fail every lookup. Giving up the parameter costs one retry and
    # leaves the reader with a slow answer instead of none.
    def recover_from(error)
      @omit_reasoning_effort = true if error.message.include?("reasoning_effort")
    end

    def content_from(response)
      response.dig("choices", 0, "message", "content")
    end
  end
end
