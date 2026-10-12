require "test_helper"

# Each provider's own refusal, as it answers it, run through RubyLLM's middleware, then read by the class RubyLLM raised.
# Text is read only where a provider still says it in words alone (FirefightAi::Credit).
class FirefightAi::RefusalClassesTest < ActiveSupport::TestCase
  include FakeProviderHelper

  OPENAI = { openai_api_key: "sk-test" }.freeze
  ANTHROPIC = { anthropic_api_key: "sk-ant-test" }.freeze
  OPENROUTER = { openrouter_api_key: "sk-or-test" }.freeze
  GEMINI = { gemini_api_key: "gemini-test" }.freeze

  setup { FakeProviderHelper::Adapter.reset! }

  # Seen in dev: OpenAI's tokens per minute limit came back as a bad request. RubyLLM now raises it as a rate limit.
  test "OpenAI's tokens per minute limit said as a bad request is a rate limit, retried and backed up" do
    error = openai(400, "Rate limit reached for gpt-4o on tokens per min (TPM). Please try again in 5.84s.")

    assert_kind_of RubyLLM::RateLimitError, error
    assert_equal "RateLimitError", translated(error).reason
    assert_kind_of FirefightAi::TransientError, translated(error)
    assert FirefightAi.provider_down?(error)
    assert_equal FirefightAi::CAUSE_DOWN, FirefightAi.cause(error)
  end

  test "an overload is retried and backed up, as a 529 or said as a bad request" do
    [ anthropic(529, "overloaded_error", "Overloaded"), anthropic(400, "invalid_request_error", "The model is currently overloaded.") ].each do |error|
      assert_kind_of RubyLLM::OverloadedError, error
      assert_kind_of FirefightAi::TransientError, translated(error)
      assert FirefightAi.backup_helps?(error)
    end
  end

  test "a refused key is the key refused, whatever status it came with" do
    [ anthropic(401, "authentication_error", "invalid x-api-key"), gemini(400, "API key not valid. Please pass a valid API key.") ].each do |error|
      assert_kind_of RubyLLM::UnauthorizedError, error
      assert_equal FirefightAi::CAUSE_KEY_REFUSED, FirefightAi.cause(error)
      assert AiPayer.key_refused?(error)
      assert_not FirefightAi.backup_helps?(error)
    end
  end

  test "Anthropic's balance too low is a payment refusal, out of credit by its class" do
    error = anthropic(400, "invalid_request_error", "Your credit balance is too low to access the Anthropic API.")

    assert_kind_of RubyLLM::PaymentRequiredError, error
    assert_raises(FirefightAi::OutOfCredit) { FirefightAi.translating_errors { raise error } }
    assert_equal FirefightAi::CAUSE_OUT_OF_CREDIT, FirefightAi.cause(error)
    assert_equal Chat::ModelSwitch::CAUSE_OUT_OF_CREDIT, Chat::ModelSwitch.cause_of(error)
  end

  test "OpenRouter's spent credits and DeepSeek's spent balance are payment refusals" do
    error = openrouter(402, "Insufficient credits. Add more using https://openrouter.ai/settings/credits")

    assert_kind_of RubyLLM::PaymentRequiredError, error
    assert AiPayer.out_of_credit?(error)
  end

  # The four that RubyLLM raises under a class that means something else, which only their code or their words tell apart.
  test "a spent balance said as a rate limit, a refused key or a bad request is still out of credit" do
    quota = provider_error(:openai, "gpt-4o", status: 429, body: { error: { message: "You exceeded your current quota.", type: "insufficient_quota", code: "insufficient_quota" } }, **OPENAI)
    gemini = gemini(429, "Your prepayment credits are depleted. Please go to AI Studio to manage your project and billing.")
    key_limit = openrouter(403, "Key limit exceeded (total limit). Manage it using https://openrouter.ai/settings/keys")
    usage_limit = anthropic(400, "invalid_request_error", "You have reached your specified API usage limits. You will regain access on 2026-11-01.")

    assert_equal [ RubyLLM::RateLimitError, RubyLLM::RateLimitError, RubyLLM::ForbiddenError, RubyLLM::BadRequestError ],
                 [ quota, gemini, key_limit, usage_limit ].map(&:class)
    [ quota, gemini, key_limit, usage_limit ].each do |error|
      assert_equal FirefightAi::CAUSE_OUT_OF_CREDIT, FirefightAi.cause(error), error.message
      assert_not FirefightAi.provider_down?(error), "#{error.message} is credit, never the provider down"
    end
  end

  # Seen live: every chat turn answered "something went wrong" once OpenRouter's workspace budget was spent.
  test "OpenRouter's spent workspace budget is a refused key by its class and out of credit by the limit it names" do
    body = {
      error: {
        message: "Workspace lifetime budget of $140.00 exceeded. Contact your org admin. $140.03 of $140.00 used; does not reset.", code: 403,
        metadata: { limit_source: "openrouter_workspace_budget", remedy_hint: "Ask your org admin to raise the workspace budget.",
                    scope: "workspace", limit_usd: 140, spend_usd: 140.03, resets_at: nil }
      }
    }
    error = provider_error(:openrouter, "deepseek/deepseek-v4-pro", status: 403, body: body, **OPENROUTER)

    assert_kind_of RubyLLM::ForbiddenError, error
    assert_equal FirefightAi::CAUSE_OUT_OF_CREDIT, FirefightAi.cause(error)
    assert_kind_of FirefightAi::OutOfCredit, translated(error)
    assert_not FirefightAi.backup_helps?(error)
    assert_equal "The account has no credit left.", AiAccountError.words(error, model: "deepseek/deepseek-v4-pro")
  end

  test "a 403 OpenRouter sends for anything but a spent limit stays the key refused" do
    error = openrouter(403, "The model deepseek/deepseek-v4-pro is not allowed by your key's provider settings.")

    assert_equal FirefightAi::CAUSE_KEY_REFUSED, FirefightAi.cause(error)
    assert_not_kind_of FirefightAi::OutOfCredit, translated(error)
  end

  test "a conversation too long is said by its class, so the loop makes room once" do
    error = anthropic(400, "invalid_request_error", "prompt is too long: 210000 tokens > 200000 maximum")

    assert_kind_of RubyLLM::ContextLengthExceededError, error
    assert_kind_of FirefightAi::TerminalError, translated(error)
  end

  test "a model not there for the account is unavailable, which a backup helps with" do
    error = anthropic(404, "not_found_error", "model: claude-haiku-9")

    assert FirefightAi.model_unavailable?(error)
    assert_equal Chat::ModelSwitch::CAUSE_UNAVAILABLE, Chat::ModelSwitch.cause_of(error)
    assert FirefightAi.backup_helps?(error)
  end

  private

  def translated(error)
    FirefightAi.translated(error)
  end

  def openai(status, message) = provider_error(:openai, "gpt-4o", status: status, body: { error: { message: message } }, **OPENAI)

  def anthropic(status, type, message)
    provider_error(:anthropic, "claude-haiku-4-5", status: status, body: { type: "error", error: { type: type, message: message } }, **ANTHROPIC)
  end

  def openrouter(status, message)
    provider_error(:openrouter, "anthropic/claude-haiku-4.5", status: status, body: { error: { message: message, code: status } }, **OPENROUTER)
  end

  def gemini(status, message)
    provider_error(:gemini, "gemini-2.5-flash", status: status, body: { error: { code: status, message: message, status: "INVALID_ARGUMENT" } }, **GEMINI)
  end
end
