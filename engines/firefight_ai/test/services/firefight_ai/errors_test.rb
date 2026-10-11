require "test_helper"

class FirefightAi::ErrorsTest < ActiveSupport::TestCase
  test "a rate limit is worth retrying" do
    error = assert_raises(FirefightAi::TransientError) do
      FirefightAi.translating_errors { raise RubyLLM::RateLimitError.new("slow down") }
    end

    assert_equal "RateLimitError", error.reason
  end

  test "a bad request that is not a rate limit is still terminal" do
    assert_raises(FirefightAi::TerminalError) do
      FirefightAi.translating_errors { raise RubyLLM::BadRequestError.new("Invalid request - please check your input") }
    end
  end
end
