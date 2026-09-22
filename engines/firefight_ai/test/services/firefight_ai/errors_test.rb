require "test_helper"

class FirefightAi::ErrorsTest < ActiveSupport::TestCase
  test "a rate limit is worth retrying" do
    error = assert_raises(FirefightAi::TransientError) do
      FirefightAi.translating_errors { raise RubyLLM::RateLimitError.new("slow down") }
    end

    assert_equal "RateLimitError", error.reason
  end

  # Seen in dev: OpenAI's tokens per minute limit came back as a 429 the library raised as a bad
  # request, so the turn was given up on instead of retried six seconds later.
  test "a rate limit the library mislabels is still worth retrying, by its status" do
    response = Struct.new(:status, :body).new(429, "Rate limit reached for gpt-4o on tokens per min (TPM)")

    error = assert_raises(FirefightAi::TransientError) do
      FirefightAi.translating_errors { raise RubyLLM::BadRequestError.new(nil, response: response) }
    end

    assert_equal "RateLimitError", error.reason
  end

  test "a rate limit the library mislabels with no status is still known by its words" do
    error = assert_raises(FirefightAi::TransientError) do
      FirefightAi.translating_errors { raise RubyLLM::BadRequestError.new("Rate limit reached for gpt-4o. Please try again in 5.84s.") }
    end

    assert_equal "RateLimitError", error.reason
  end

  test "a bad request that is not a rate limit is still terminal" do
    assert_raises(FirefightAi::TerminalError) do
      FirefightAi.translating_errors { raise RubyLLM::BadRequestError.new("Invalid request - please check your input") }
    end
  end
end
