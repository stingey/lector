class Translator
  class AnthropicProvider < BaseProvider
    DEFAULT_MODEL = "claude-haiku-4-5".freeze
    API_VERSION = "2023-06-01".freeze

    def model
      ENV.fetch("TRANSLATOR_MODEL", DEFAULT_MODEL)
    end

    private

    def api_key
      ENV["TRANSLATOR_API_KEY"].presence || ENV["ANTHROPIC_API_KEY"].presence
    end

    def endpoint
      base = ENV.fetch("TRANSLATOR_BASE_URL", "https://api.anthropic.com/v1").chomp("/")
      "#{base}/messages"
    end

    def headers
      {
        "Content-Type" => "application/json",
        "x-api-key" => api_key,
        "anthropic-version" => API_VERSION
      }
    end

    def body(system:, user:)
      {
        model: model,
        max_tokens: 400,
        system: system,
        messages: [ { role: "user", content: user } ]
      }
    end

    def content_from(response)
      Array(response["content"]).filter_map { |part| part["text"] }.join
    end
  end
end
