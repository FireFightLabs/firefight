require "test_helper"

class Conversation::ToolsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @conversation = @workspace.conversations.create!(
      subject: @incident, kind: Conversation::KIND_CHANNEL, channel_id: @incident.channel_id,
      thread_id: "1700000000.000100", started_by: workspace_memberships(:alice_workspace_one),
      max_turns: 40, max_spend_cents: 50
    )
    FeatureFlags.stubs(:enabled?).returns(true)
    Entitlements.stubs(:allows?).returns(true)
    Ability::Grant.create!(
      workspace: @workspace, principal: workspace_memberships(:alice_workspace_one),
      action: Ability::Action.system!(
        Ability::Action.system_key(Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE)
      )
    )
  end

  test "a conversation starts with only the tools it always needs" do
    names = Conversation::Tools.for(turn, offer: ->(_tools) { }).map(&:name)

    assert_equal [ "open_tools", "read_result", "start_investigation" ], names
  end

  test "someone who may not start a run is refused, in their name" do
    AbilityGateway.stubs(:permitted?).returns(false)

    assert_no_difference "Investigation.count" do
      assert_match "not allowed to start an investigation", tool.call[:error]
    end
  end

  test "a run that needs approval is not started until someone approves it" do
    start = Ability::Action.system!(
      Ability::Action.system_key(Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE)
    )
    @workspace.policies.create!(domain: Policy::DOMAIN_APPROVALS, name: "Approvals").policy_rules.create!(
      priority: 1,
      conditions: [ { field: "risk_level", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ start.risk_level ] } ],
      outcome: { "require" => { "role" => WorkspaceMembership.roles[:admin], "count" => 1 } }
    )

    assert_no_difference "Investigation.count" do
      assert_match "not allowed to start an investigation", tool.call[:error]
    end
  end

  test "starting a run is written to the ledger and closed off" do
    tool.call

    invocation = @workspace.ability_invocations.find_by!(action_key: Ability::Action.system_key(
      Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE
    ))
    assert_equal Ability::Invocation::DECISION_ALLOW, invocation.decision
    assert invocation.completed_at
  end

  test "the chat hands over what the person said, so the run starts from it" do
    # RubyLLM hands arguments over keyed by text.
    tool.call(**{ "symptom" => "checkout is slow", "started_around" => "2026-09-24T12:00:00Z", "names" => [ "checkout" ] })

    brief = @workspace.investigations.sole.brief
    assert_equal "checkout is slow", brief[Investigation::Brief::KEY_SYMPTOM]
    assert_equal "2026-09-24T12:00:00Z", brief[Investigation::Brief::KEY_STARTED_AROUND]
    assert_equal Investigation::Brief::SOURCE_CHAT, brief[Investigation::Brief::KEY_SOURCE]
  end

  test "the agent can hand a question over to a full investigation" do
    assert_difference "Investigation.count", 1 do
      assert_match "Started", tool.call
    end

    investigation = @workspace.investigations.sole
    assert_equal @incident, investigation.subject
    assert_equal @conversation.started_by, investigation.triggered_by
    assert_equal Investigation::TRIGGER_CONVERSATION, investigation.trigger_source
  end

  test "a run already going is said plainly rather than started twice" do
    tool.call

    assert_equal Investigation.already_running_message(@incident), tool.call[:error]
  end

  test "a conversation about no incident says so" do
    @conversation.update!(subject: nil)

    assert_match "no incident here", tool.call[:error]
  end

  # The refusal still goes to the model as text, so without the mark the card would say Completed.
  test "a refusal is remembered as failed on the saved call" do
    @conversation.update!(subject: nil)
    call = RubyLLM::ToolCall.new(id: "call_1", name: Mcp::Tools::START_INVESTIGATION, arguments: {})
    @conversation.chat_record.add_message(RubyLLM::Message.new(role: :assistant, content: "", tool_calls: { "call_1" => call }))

    tool.call(tool_call: call)

    assert_equal [ "call_1" ], @conversation.chat.failed_tool_call_ids
  end

  private

  def turn = Conversation::Turn.new(@conversation, asker: workspace_memberships(:alice_workspace_one))

  def tool = Conversation::Tools::StartInvestigation.new(turn)
end
