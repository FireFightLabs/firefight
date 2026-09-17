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

  test "a conversation starts with the two tools it always needs" do
    names = Conversation::Tools.for(@conversation, offer: ->(_tools) { }).map(&:name)

    assert_equal [ "find_tools", "start_investigation" ], names
  end

  test "someone who may not start a run is refused, in their name" do
    AbilityGateway.stubs(:permitted?).returns(false)

    assert_no_difference "Investigation.count" do
      assert_match "not allowed to start an investigation", tool.execute[:error]
    end
  end

  test "the agent can hand a question over to a full investigation" do
    assert_difference "Investigation.count", 1 do
      assert_match "Started", tool.execute
    end

    investigation = @workspace.investigations.sole
    assert_equal @incident, investigation.subject
    assert_equal @conversation.started_by, investigation.triggered_by
    assert_equal Investigation::TRIGGER_CONVERSATION, investigation.trigger_source
  end

  test "a run already going is said plainly rather than started twice" do
    tool.execute

    assert_match "already running", tool.execute[:error]
  end

  test "a conversation about no incident says so" do
    @conversation.update!(subject: nil)

    assert_match "no incident here", tool.execute[:error]
  end

  private

  def tool = Conversation::Tools::StartInvestigation.new(@conversation)
end
