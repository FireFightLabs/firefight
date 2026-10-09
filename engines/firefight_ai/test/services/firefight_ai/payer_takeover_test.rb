require "test_helper"

# When a workspace's own AI account runs dry or has its key refused, the next one in its order carries on, from the same
# call or the same step of a run, and every call is in the ledger under whoever paid for it.
class FirefightAi::PayerTakeoverTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  Response = Struct.new(:status, :body, :headers)

  # A saved chat as the loop sees it, recording which model and context each turn ran on.
  class FakeChat
    attr_reader :messages, :turns, :model_id, :provider

    def initialize(replies, model_id:)
      @replies = replies
      @messages = []
      @turns = []
      @model_id = model_id
    end

    def to_llm = self
    def awaiting_approval? = false
    def with_max_output_tokens(_limit) = self

    def with_context(context)
      @context = context
      self
    end

    def with_model(model, provider: nil, assume_model_exists: false)
      @model_id = model
      @provider = provider
      self
    end

    def step(&)
      @turns << [ @model_id, @context&.config&.anthropic_api_key || @context&.config&.openai_api_key ]
      reply = @replies.shift
      raise reply if reply.is_a?(Exception)

      messages << reply
      reply
    end
  end

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "a call the first account cannot pay for is made on the next, and the first is set aside once" do
    first = add_ai_account!(@workspace, key: "sk-ant-first", label: "First")
    second = add_ai_account!(@workspace, provider: "openai", key: "sk-openai-second", label: "Second")
    keys = []
    FirefightAi.stubs(:chat).with { |choice| keys << choice.context.config.public_send("#{choice.provider}_api_key") }.returns(FakeChat.new([], model_id: nil))
    calls = 0

    assert_enqueued_jobs 1, only: WorkspaceAiAccountNoticeJob do
      FirefightAi.generate(FirefightAi.model_for(AiPurpose::SUMMARY, workspace: @workspace), purpose: AiPurpose::SUMMARY, inference: context) do
        calls += 1
        raise payment_required if calls == 1

        llm_reply(content: "summary", output: 20, cost: 0.001)
      end
    end

    assert_equal [ "sk-ant-first", "sk-openai-second" ], keys
    refused, answered = Inference.where(workspace: @workspace, feature: "takeover_test").order(:created_at).to_a
    assert_equal [ Inference::STATUS_ERROR, Inference::PAID_BY_ACCOUNT, first.id, "anthropic" ],
                 [ refused.status, refused.paid_by, refused.workspace_ai_account_id, refused.provider ]
    assert_equal [ Inference::STATUS_SUCCESS, Inference::PAID_BY_ACCOUNT, second.id, "openai", "gpt-4o-mini" ],
                 [ answered.status, answered.paid_by, answered.workspace_ai_account_id, answered.provider, answered.model ]
    assert_nil answered.billed_micros, "the provider bills its own account, Firefight bills nothing"
    assert_equal :out_of_credit, first.reload.state
    assert_not_nil second.reload.last_used_at
    assert_empty AiAccount.out_of_credit, "the deployment's own account is untouched"
  end

  test "a refused key hands the call to the operator's keys after the workspace's own" do
    account = add_ai_account!(@workspace)
    FirefightAi.stubs(:chat).returns(FakeChat.new([], model_id: nil))
    calls = 0

    FirefightAi.generate(FirefightAi.model_for(AiPurpose::SUMMARY, workspace: @workspace), purpose: AiPurpose::SUMMARY, inference: context) do
      calls += 1
      raise RubyLLM::UnauthorizedError.new("invalid x-api-key", response: Response.new(401, {}, {})) if calls == 1

      llm_reply(content: "summary")
    end

    assert_equal :failing, account.reload.state
    assert_equal "The provider refused the key.", account.last_error
    assert_equal Inference::PAID_BY_OPERATOR, Inference.where(workspace: @workspace, feature: "takeover_test", status: Inference::STATUS_SUCCESS).sole.paid_by
  end

  test "with nobody left to pay the call is out of credit, which says where an admin fixes it" do
    on_firefights_cloud!
    add_ai_account!(@workspace)
    FirefightAi.stubs(:chat).returns(FakeChat.new([], model_id: nil))

    error = assert_raises(FirefightAi::OutOfCredit) do
      FirefightAi.generate(FirefightAi.model_for(AiPurpose::SUMMARY, workspace: @workspace), purpose: AiPurpose::SUMMARY, inference: context) do
        raise payment_required
      end
    end

    assert AiCredit.out?(error)
    assert_match "this workspace's AI account is out of credit", AiCredit.cannot(@workspace)
  end

  test "a run whose account runs dry carries on at the same step on the next account's model and key" do
    add_ai_account!(@workspace, key: "sk-ant-first", label: "First")
    add_ai_account!(@workspace, provider: "openai", key: "sk-openai-second", label: "Second")
    choice = FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: @workspace)
    answer = RubyLLM::Message.new(role: :assistant, content: "the answer", output_tokens: 10)
    answer.stubs(:cost).returns(stub(total: 0.0))
    chat = FakeChat.new([ payment_required, answer ], model_id: choice.model)
    FirefightAi.bind(chat, choice)

    outcome = FirefightAi::AgentLoop.new(
      chat: chat, answered: -> { false }, reply_is_answer: true, choice: choice, purpose: AiPurpose::INVESTIGATION,
      budget: FirefightAi::AgentLoop::Budget.new(max_spend_cents: 400, max_turns: 50),
      inference: { workspace: @workspace, feature: "takeover_loop", inferable: @incident },
      output: FirefightAi.output_cap(AiPurpose::INVESTIGATION, choice: choice)
    ).run

    assert_equal FirefightAi::AgentLoop::STATUS_ANSWERED, outcome.status
    assert_equal [ [ "claude-sonnet-4-5", "sk-ant-first" ], [ "gpt-4o", "sk-openai-second" ] ], chat.turns
    assert_equal [ "anthropic", "openai" ], Inference.where(workspace: @workspace, feature: "takeover_loop").order(:created_at).pluck(:provider)
  end

  private

  def payment_required
    body = { "error" => { "code" => 402, "message" => "Insufficient credits" } }
    RubyLLM::PaymentRequiredError.new("Insufficient credits", response: Response.new(402, body, {}))
  end

  def context
    { workspace: @workspace, feature: "takeover_test", inferable: @incident }
  end
end
