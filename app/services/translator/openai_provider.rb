class Translator
  # Works with OpenAI and with anything that speaks its chat-completions dialect,
  # which includes Gemini's compatibility endpoint, Groq, and OpenRouter. Point
  # TRANSLATOR_BASE_URL at whichever one you want.
  class OpenaiProvider < BaseProvider
    DEFAULT_BASE_URL = "https://api.openai.com/v1".freeze
    DEFAULT_MODEL = "gpt-5-mini".freeze

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
      {
        model: model,
        messages: [
          { role: "system", content: system },
          { role: "user", content: user }
        ],
        response_format: { type: "json_object" }
      }
    end

    def content_from(response)
      response.dig("choices", 0, "message", "content")
    end
  end
end
