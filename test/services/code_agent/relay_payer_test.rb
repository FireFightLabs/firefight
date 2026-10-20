require "test_helper"

# A code fix runs on the payer the workspace's order chose. The proxy forwards with that payer's own key, which never
# leaves Firefight, and the ledger says who paid.
class CodeAgent::RelayPayerTest < ActiveSupport::TestCase
  FakeProxy = Struct.new(:usage, :status, :refusal, :request_id) do
    def forward(**) = usage

    def trim = nil

    def calls = FirefightAi::ModelProxy::Calls.new
  end

  setup do
    @workspace = workspaces(:slack_workspace_one)
    RubyLLM.config.stubs(:anthropic_api_key).returns("sk-firefight-own")
  end

  test "a change paid by the workspace's own account is forwarded with its key, never Firefight's" do
    account = add_ai_account!(@workspace, key: "sk-ant-workspace")
    session, = CodeAgentSession.open!(workspace: @workspace, choice: FirefightAi.model_for(AiPurpose::CODE_FIX, workspace: @workspace), repository: "acme/api")
    keys = []
    FirefightAi::ModelProxy.expects(:new).with { |provider, config:, connect_to:| keys << [ provider, config&.anthropic_api_key, connect_to ] }
                           .returns(FakeProxy.new(FirefightAi::ModelProxy::Usage.new(input: 10, output: 5, cache_read: 0, cache_write: 0), 200, nil, "req_011CODE"))

    CodeAgent::Relay.new(session).forward(path: "messages", body: "{}", headers: {}) { |*| nil }

    assert_equal [ [ "anthropic", "sk-ant-workspace", nil ] ], keys
    inference = Inference.find_by!(inferable: session)
    assert_equal [ Inference::PAID_BY_ACCOUNT, account ], [ inference.paid_by, inference.workspace_ai_account ]
    assert_equal "req_011CODE", inference.provider_request_id
    assert_not_nil account.reload.last_used_at
  end

  test "a call is priced at the hour it was sent, not the hour its answer ended" do
    session, = CodeAgentSession.open!(workspace: @workspace, choice: FirefightAi::ModelChoice.new(model: "claude-sonnet-5", provider: "anthropic"),
                                      repository: "acme/api")
    sent = Time.utc(2026, 10, 20, 9, 59)
    usage = FirefightAi::ModelProxy::Usage.new(input: 10, output: 5, cache_read: 0, cache_write: 0)
    proxy = FakeProxy.new(usage, 200, nil, "req_011SENT")
    test = self
    proxy.define_singleton_method(:forward) do |**|
      test.travel_to(Time.utc(2026, 10, 20, 10, 1))
      usage
    end
    FirefightAi::ModelProxy.stubs(:new).returns(proxy)
    FirefightAi.expects(:cost_micros).with { |*params| params.last[:at] == sent }.returns(1_234)

    travel_to(sent) { CodeAgent::Relay.new(session).forward(path: "messages", body: "{}", headers: {}) { |*| nil } }

    assert_equal 1_234, Inference.find_by!(inferable: session).cost_micros
  end

  test "a change on the deployment's own account forwards with the deployment's configuration" do
    session, = CodeAgentSession.open!(workspace: @workspace, choice: FirefightAi::ModelChoice.new(model: "claude-sonnet-5", provider: "anthropic"),
                                      repository: "acme/api")

    assert_nil session.llm_config
    assert_equal Inference::PAID_BY_OPERATOR, session.paid_by
  end

  test "an account removed while its change runs stops the change rather than moving it onto another account" do
    account = add_ai_account!(@workspace)
    session, = CodeAgentSession.open!(workspace: @workspace, choice: FirefightAi.model_for(AiPurpose::CODE_FIX, workspace: @workspace), repository: "acme/api")
    account.destroy!

    error = assert_raises(FirefightAi::ModelProxy::Refused) { CodeAgent::Relay.new(session.reload).forward(path: "messages", body: "{}", headers: {}) { |*| nil } }
    assert_equal CodeAgentSession::ACCOUNT_GONE, error.message
    assert_equal 0, session.reload.calls_running
  end
end
