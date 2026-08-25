require "test_helper"

class Translator::OpenaiProviderTest < ActiveSupport::TestCase
  test "the original gpt-5 line is held to minimal reasoning so a lookup does not stall" do
    body = with_env("TRANSLATOR_MODEL" => "gpt-5-mini") { request_body }

    assert_equal "minimal", body[:reasoning_effort]
  end

  test "later gpt-5 generations are held to low, the floor they accept instead" do
    body = with_env("TRANSLATOR_MODEL" => "gpt-5.4-mini") { request_body }

    assert_equal "low", body[:reasoning_effort]
  end

  test "the model shipped by default asks for an effort its own generation accepts" do
    body = with_env("TRANSLATOR_MODEL" => nil) { request_body }

    assert_equal Translator::OpenaiProvider::DEFAULT_MODEL, body[:model]
    assert_equal "low", body[:reasoning_effort]
  end

  test "the effort can be raised when a lookup deserves deliberation" do
    body = with_env("TRANSLATOR_MODEL" => "gpt-5", "TRANSLATOR_REASONING_EFFORT" => "high") { request_body }

    assert_equal "high", body[:reasoning_effort]
  end

  test "an empty effort omits the parameter" do
    body = with_env("TRANSLATOR_MODEL" => "gpt-5-mini", "TRANSLATOR_REASONING_EFFORT" => "") { request_body }

    assert_not body.key?(:reasoning_effort)
  end

  test "models that reject the parameter never receive it" do
    body = with_env("TRANSLATOR_MODEL" => "gpt-4.1-mini", "TRANSLATOR_REASONING_EFFORT" => "minimal") { request_body }

    assert_not body.key?(:reasoning_effort)
  end

  test "a model that rejects the effort gives up the parameter rather than the lookup" do
    provider = Translator::OpenaiProvider.new
    rejection = Translator::Error.new("HTTP 400: Unsupported value: 'reasoning_effort' does not support 'low'")

    with_env("TRANSLATOR_MODEL" => "gpt-5.9-mini") do
      assert_equal "low", body_from(provider)[:reasoning_effort]

      provider.send(:recover_from, rejection)

      assert_not body_from(provider).key?(:reasoning_effort)
    end
  end

  test "an unrelated failure leaves the request alone so the retry is a real retry" do
    provider = Translator::OpenaiProvider.new

    with_env("TRANSLATOR_MODEL" => "gpt-5.4-mini") do
      provider.send(:recover_from, Net::ReadTimeout.new)

      assert_equal "low", body_from(provider)[:reasoning_effort]
    end
  end

  test "the prompt and json response format survive" do
    body = with_env("TRANSLATOR_MODEL" => "gpt-5-mini") { request_body }

    assert_equal "gpt-5-mini", body[:model]
    assert_equal [ "you are a helper", "explain this word" ], body[:messages].map { |message| message[:content] }
    assert_equal({ type: "json_object" }, body[:response_format])
  end

  private

  def request_body
    body_from(Translator::OpenaiProvider.new)
  end

  def body_from(provider)
    provider.send(:body, system: "you are a helper", user: "explain this word")
  end

  def with_env(values)
    previous = values.keys.index_with { |key| ENV[key] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end
end
