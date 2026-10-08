require "test_helper"

# Seen in a real chat, a fix touched a path the connection's Code changes setting keeps Halon out of. The refusal reached
# Halon as "github.fix_code failed", which the instructions call a provider failure to try another way around, so Halon
# blamed GitHub's safeguard and went looking for another way. A refusal by one of Firefight's own rules is Firefight's,
# final, and ledgered as a refusal.
class Chat::Tools::PolicyRefusalsTest < ActiveSupport::TestCase
  REASON = "Halon may not change .github/workflows/ci.yml in acme/api. An admin can change this under Integrations, Fake, Code changes.".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    member = workspace_memberships(:alice_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: member)
    @turn = Conversation::Turn.new(@conversation, asker: member)
    @chat = @conversation.chat_record

    fake = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "fake", name: "Fake")
    fake.integration_environments.create!(credentials: { token: "x" }.to_json)
    @writes = fake.tools.create!(name: "write_thing", description: "Writes", params_schema: {}, enabled: true, read_only: false)
    Integrations::NativePack.stubs(:for).with("fake").returns(FakeNativePack)
    Integrations::NativeExecutor.stubs(:call).raises(Integrations::PolicyRefusal, REASON)
  end

  test "a chat is handed the rule's reason as Firefight's own and final, never as the provider failing" do
    said = call(@writes)

    assert_equal FirefightAi::Evidence.refused(@writes.model_facing_name, REASON), said
    assert_no_match(/failed/, said)
    saved = @chat.outcome_call("call_1")
    assert_equal [ true, Chat::StepOutcome::FAILURE_ERROR ], [ saved.failed, saved.failure_kind ]
  end

  test "the ledger records the call as refused with the rule's reason, not as an error" do
    call(@writes)

    invocation = Ability::Invocation.find_by!(workspace: @workspace, action_key: @writes.action_key)
    assert_equal [ Ability::Invocation::OUTCOME_REFUSED, REASON ], [ invocation.outcome, invocation.error_summary ]
  end

  test "a run keeps the refusal on its step, cited by its number, and the ledger row behind it says refused" do
    investigation = run_on_incident
    Ability::Grant.create!(workspace: @workspace, principal: investigation.acting_principal, action: @writes.reload.ability_action)
    investigation.stubs(:reads_only?).returns(false)

    said = Chat::Tools::Connection.new(investigation, @writes).call

    step = investigation.steps.ordered.first
    assert_equal FirefightAi::Evidence.refused(@writes.model_facing_name, REASON, step: step.position), said
    assert_equal [ Investigation::Step::STATUS_SUCCEEDED, Chat::StepOutcome::FAILURE_ERROR ], [ step.status, step.failure_kind ]
    assert_equal Ability::Invocation::OUTCOME_REFUSED, step.invocation.outcome
  end

  test "a call a read guard refuses while investigating reaches the run as Firefight's own rule too" do
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank")
    northflank.integration_environments.create!(credentials: { token: "x" }.to_json)
    api = northflank.tools.create!(name: "api_request", description: "Calls the API", enabled: true, read_only: false,
                                   params_schema: { "type" => "object", "properties" => { "method" => { "type" => "string" }, "path" => { "type" => "string" } } })

    said = Chat::Tools::Connection.new(run_on_incident, api).call(method: "POST", path: "services/web/restart")

    assert said.end_with?("\n#{FirefightAi::Evidence::REFUSED_BY_RULE}")
    assert_includes said, "only reads, so its method must be GET"
    assert_no_match(/failed/, said)
  end

  private

  def run_on_incident
    @workspace.investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400
    )
  end

  # The loop saves the model's call before running the tool. Here the call is saved by hand.
  def call(tool, id: "call_1", **arguments)
    llm_call = RubyLLM::ToolCall.new(id: id, name: tool.model_facing_name, arguments: arguments.stringify_keys)
    @chat.add_message(RubyLLM::Message.new(role: :assistant, content: "", tool_calls: { id => llm_call }))
    Chat::Tools::Connection.new(@turn, tool).call(tool_call: llm_call, **arguments)
  end
end
