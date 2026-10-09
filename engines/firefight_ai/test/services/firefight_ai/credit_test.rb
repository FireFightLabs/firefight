require "test_helper"

class FirefightAi::CreditTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  Response = Struct.new(:status, :body, :headers)

  # OpenRouter's documented error shape, with the words it said in dev when the balance was $0.07.
  OPENROUTER_SHORT = {
    "error" => {
      "code" => 402,
      "message" => "This request requires more credits, or fewer max_tokens. You requested up to 65536 tokens, " \
                   "but can only afford 60329. To increase, visit https://openrouter.ai/settings/credits and upgrade to a paid account"
    }
  }.freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @original_env = ENV.slice("POSTMORTEM_AI_MAX_OUTPUT_TOKENS")
    ENV.delete("POSTMORTEM_AI_MAX_OUTPUT_TOKENS")
    FirefightAi.stubs(:chat).returns(FakeChat.new([]))
  end

  teardown do
    ENV.delete("POSTMORTEM_AI_MAX_OUTPUT_TOKENS")
    ENV.update(@original_env)
  end

  test "a 402 naming what the balance covers is out of credit, with that amount" do
    credit = FirefightAi::Credit.from(payment_required(OPENROUTER_SHORT))

    assert credit.out_of_credit?
    assert_equal 60_329, credit.affordable
  end

  test "OpenRouter's in-flight 402 is a wait, never a spent balance" do
    with_header = payment_required({ "error" => { "code" => 402, "message" => "Too much in flight" } }, headers: { "Retry-After" => "3" })
    by_source = payment_required({ "error" => { "code" => 402, "message" => "Too much in flight", "metadata" => { "limit_source" => "openrouter_in_flight_budget" } } })

    [ with_header, by_source ].each do |error|
      translated = assert_raises(FirefightAi::TransientError) { FirefightAi.translating_errors { raise error } }
      assert_equal FirefightAi::IN_FLIGHT, translated.reason
    end
  end

  # OpenAI says a spent balance with a 429, which would otherwise be retried as a rate limit forever.
  test "OpenAI's insufficient_quota is out of credit, not a rate limit" do
    body = { "error" => { "message" => "You exceeded your current quota, please check your plan and billing details.", "type" => "insufficient_quota", "code" => "insufficient_quota" } }
    error = RubyLLM::RateLimitError.new(body.dig("error", "message"), response: Response.new(429, body, {}))

    assert_raises(FirefightAi::OutOfCredit) { FirefightAi.translating_errors { raise error } }
  end

  test "Anthropic's billing error and its balance too low are out of credit" do
    billing = payment_required({ "type" => "error", "error" => { "type" => "billing_error", "message" => "There's an issue with your billing." } })
    low = RubyLLM::BadRequestError.new("Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits.",
                                       response: Response.new(400, {}, {}))

    [ billing, low ].each do |error|
      assert_raises(FirefightAi::OutOfCredit) { FirefightAi.translating_errors { raise error } }
    end
  end

  test "out of credit is terminal and logged for alerting under one event name" do
    logged = []
    Rails.logger.stubs(:error).with { |line| logged << line }

    error = assert_raises(FirefightAi::OutOfCredit) { FirefightAi.translating_errors { raise payment_required(OPENROUTER_SHORT) } }

    assert_kind_of FirefightAi::TerminalError, error
    assert_equal "OutOfCredit", error.reason
    assert(logged.any? { |line| JSON.parse(line)["event"] == FirefightAi::OUT_OF_CREDIT_EVENT })
  end

  test "an ordinary bad request is still terminal and not out of credit" do
    error = assert_raises(FirefightAi::TerminalError) do
      FirefightAi.translating_errors { raise RubyLLM::BadRequestError.new("Invalid request - please check your input") }
    end

    assert_not_kind_of FirefightAi::OutOfCredit, error
  end

  test "each purpose reserves what it writes, never the model's own maximum" do
    caps = AiPurpose::ALL.excluding(AiPurpose::CODE_FIX).index_with { |purpose| FirefightAi.output_cap(purpose, choice: FirefightAi::ModelChoice.new(model: "gpt-4o", provider: nil)) }

    assert_equal 16_000, caps[AiPurpose::INVESTIGATION].max
    assert_equal 16_000, caps[AiPurpose::POSTMORTEM].max
    assert_equal 8_000, caps[AiPurpose::CITATION_CHECK].max
    assert_equal 4_000, caps[AiPurpose::SUMMARY].max
    caps.each_value { |cap| assert_operator cap.floor, :<, cap.max }
  end

  test "a purpose's env var sets its maximum, and the registry's limit for the model still holds" do
    ENV["POSTMORTEM_AI_MAX_OUTPUT_TOKENS"] = "24000"

    assert_equal 24_000, FirefightAi.output_cap(AiPurpose::POSTMORTEM, choice: FirefightAi::ModelChoice.new(model: "gpt-4o", provider: nil)).max
    small = FirefightAi.output_cap(AiPurpose::POSTMORTEM, choice: FirefightAi::ModelChoice.new(model: "gpt-3.5-turbo", provider: nil))
    assert_equal 4_096, small.max
    assert_equal 4_096, small.floor
  end

  test "a refusal for credit is asked again once with what the balance covers, and both calls are in the ledger" do
    limits = []
    calls = 0
    reply = llm_reply(content: "written", output: 900)

    ledger = FirefightAi.generate(FirefightAi::ModelChoice.new(model: "gpt-4o", provider: nil), purpose: AiPurpose::POSTMORTEM, inference: context) do |chat|
      limits << chat.max_output_tokens
      calls += 1
      raise payment_required(short_of(9_000)) if calls == 1

      reply
    end

    assert_equal [ 16_000, 9_000 ], limits
    refused, answered = Inference.where(workspace: @workspace, feature: "credit_test").order(:created_at).to_a
    assert_equal [ Inference::STATUS_ERROR, Inference::ERROR_OUT_OF_CREDIT, 16_000 ], [ refused.status, refused.error_kind, refused.max_output_tokens ]
    assert_equal [ Inference::STATUS_SUCCESS, nil, 9_000 ], [ answered.status, answered.error_kind, answered.max_output_tokens ]
    assert_equal answered, ledger.last
    assert_empty AiAccount.out_of_credit, "a refusal a shorter call answered is not the account running out"
  end

  test "a balance that covers less than a useful answer is out of credit, with no second call" do
    calls = 0

    assert_raises(FirefightAi::OutOfCredit) do
      FirefightAi.generate(FirefightAi::ModelChoice.new(model: "gpt-4o", provider: nil), purpose: AiPurpose::POSTMORTEM, inference: context) do
        calls += 1
        raise payment_required(short_of(900))
      end
    end

    assert_equal 1, calls
    assert_equal 1, Inference.where(workspace: @workspace, feature: "credit_test", error_kind: Inference::ERROR_OUT_OF_CREDIT).count
    assert_equal [ "openai" ], AiAccount.out_of_credit.pluck(:provider)
    assert_enqueued_with(job: AiAccountAlertJob, args: [ "openai" ])
  end

  test "a second refusal after the shorter try is out of credit, never a third call" do
    calls = 0

    assert_raises(FirefightAi::OutOfCredit) do
      FirefightAi.generate(FirefightAi::ModelChoice.new(model: "gpt-4o", provider: nil), purpose: AiPurpose::POSTMORTEM, inference: context) do
        calls += 1
        raise payment_required(short_of(calls == 1 ? 9_000 : 7_000))
      end
    end

    assert_equal 2, calls
  end

  # Stands in for a saved chat, recording the cap each turn was sent with.
  class FakeChat
    attr_reader :messages, :limits

    def initialize(replies)
      @replies = replies
      @messages = []
      @limits = []
    end

    def to_llm = self
    def awaiting_approval? = false
    def max_output_tokens = @limit

    def with_max_output_tokens(limit)
      @limit = limit
      self
    end

    def step(&)
      @limits << @limit
      reply = @replies.shift
      raise reply if reply.is_a?(Exception)

      messages << reply
      reply
    end
  end

  test "an agent turn refused for credit is tried once more with what is left, which stays the cap for the run" do
    answer = RubyLLM::Message.new(role: :assistant, content: "the answer", output_tokens: 10)
    answer.stubs(:cost).returns(stub(total: 0.0))
    chat = FakeChat.new([ payment_required(short_of(5_000)), answer ])

    outcome = run_loop(chat)

    assert_equal FirefightAi::AgentLoop::STATUS_ANSWERED, outcome.status
    assert_equal [ 16_000, 5_000 ], chat.limits
    assert_equal [ 16_000, 5_000 ], Inference.where(workspace: @workspace, feature: "credit_loop").order(:created_at).pluck(:max_output_tokens)
  end

  test "an agent turn the balance cannot pay a useful answer for raises, for the job to give up" do
    chat = FakeChat.new([ payment_required(short_of(1_000)) ])

    assert_raises(FirefightAi::OutOfCredit) { FirefightAi.translating_errors { run_loop(chat) } }
    assert_equal [ 16_000 ], chat.limits
    assert_equal [ "openai" ], AiAccount.out_of_credit.pluck(:provider)
  end

  test "OpenRouter's balance is read with the key calls are made with, and nothing is read without one or for another provider" do
    FirefightAi.configuration.stubs(:provider_settings).returns(openrouter_api_key: "sk-or-key")
    sent = nil
    ok = Net::HTTPOK.new("1.1", "200", "OK")
    ok.stubs(:body).returns({ data: { total_credits: 20.0, total_usage: 7.5 } }.to_json)
    http = mock("http")
    http.expects(:request).with { |request| sent = request }.returns(ok)
    Net::HTTP.expects(:start).with("openrouter.ai", 443, has_entries(use_ssl: true)).yields(http).returns(ok)

    assert_in_delta 12.5, FirefightAi::Balance.remaining("openrouter")
    assert_equal "Bearer sk-or-key", sent["Authorization"]
    assert_equal "/api/v1/credits", sent.path
    assert_nil FirefightAi::Balance.remaining("anthropic")

    FirefightAi.configuration.stubs(:provider_settings).returns({})
    assert_nil FirefightAi::Balance.remaining("openrouter")
  end

  test "a key OpenRouter refuses for its balance reads as nothing" do
    FirefightAi.configuration.stubs(:provider_settings).returns(openrouter_api_key: "sk-or-key")
    Net::HTTP.stubs(:start).returns(Net::HTTPForbidden.new("1.1", "403", "Forbidden"))

    assert_nil FirefightAi::Balance.remaining("openrouter")
  end

  private

  def payment_required(body, headers: {})
    RubyLLM::PaymentRequiredError.new(body.dig("error", "message"), response: Response.new(402, body, headers))
  end

  def short_of(affordable)
    { "error" => { "code" => 402, "message" => "This request requires more credits, or fewer max_tokens. You requested up to 16000 tokens, but can only afford #{affordable}." } }
  end

  def context
    { workspace: @workspace, feature: "credit_test", provider: "openai", model: "gpt-4o", inferable: @incident }
  end

  def run_loop(chat)
    FirefightAi::AgentLoop.new(
      chat: chat, answered: -> { false }, reply_is_answer: true,
      budget: FirefightAi::AgentLoop::Budget.new(max_spend_cents: 400, max_turns: 50),
      inference: { workspace: @workspace, feature: "credit_loop", provider: "openai", model: "gpt-4o", inferable: @incident },
      output: FirefightAi.output_cap(AiPurpose::INVESTIGATION, choice: FirefightAi::ModelChoice.new(model: "gpt-4o", provider: nil))
    ).run
  end
end
