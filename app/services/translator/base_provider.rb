require "net/http"

class Translator
  # Shared HTTP plumbing. Providers only describe their endpoint, headers, and
  # body shape; retries, timeouts, and JSON extraction live here.
  class BaseProvider
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 20
    MAX_ATTEMPTS = 2

    def configured?
      api_key.present?
    end

    def complete(system:, user:)
      raise Translator::Error, "#{self.class.name} is missing an API key" unless configured?

      attempts = 0
      begin
        attempts += 1
        extract_json(request(system: system, user: user))
      rescue Translator::Error, Net::OpenTimeout, Net::ReadTimeout, JSON::ParserError => error
        recover_from(error)
        retry if attempts < MAX_ATTEMPTS
        raise Translator::Error, "#{self.class.name}: #{error.message}"
      end
    end

    def model
      raise NotImplementedError
    end

    private

    def api_key
      raise NotImplementedError
    end

    def endpoint
      raise NotImplementedError
    end

    def headers
      raise NotImplementedError
    end

    def body(system:, user:)
      raise NotImplementedError
    end

    def content_from(response)
      raise NotImplementedError
    end

    # Last chance to adjust the request before the one retry. Providers that can
    # narrow a failure into something survivable override this.
    def recover_from(error)
    end

    def request(system:, user:)
      uri = URI(endpoint)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      post = Net::HTTP::Post.new(uri)
      headers.each { |name, value| post[name] = value }
      post.body = JSON.generate(body(system: system, user: user))

      response = http.request(post)

      unless response.is_a?(Net::HTTPSuccess)
        raise Translator::Error, "HTTP #{response.code}: #{response.body.to_s.truncate(200)}"
      end

      content_from(JSON.parse(response.body))
    end

    # Models occasionally wrap JSON in prose or code fences despite instructions.
    def extract_json(content)
      text = content.to_s.strip
      text = text.gsub(/\A```(?:json)?\s*/, "").gsub(/```\z/, "").strip

      JSON.parse(text)
    rescue JSON::ParserError
      match = text[/\{.*\}/m]
      raise Translator::Error, "provider did not return JSON" if match.blank?

      JSON.parse(match)
    end
  end
end
