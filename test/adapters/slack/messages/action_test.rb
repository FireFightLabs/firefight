require "test_helper"

class Slack::Messages::ActionTest < ActiveSupport::TestCase
  setup do
    @member = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "a follow-up tracked in an issue links to it, with the tracker's title escaped" do
    action = @incident.incident_actions.create!(
      created_by: @member, action_type: IncidentAction::ACTION_TYPE_FOLLOWUP,
      description: "Block <!channel> probes", external_key: "FIR-105", external_url: "https://linear.app/firefight/issue/FIR-105"
    )

    body = Slack::Messages::Action.created(action).map { |block| block.dig(:text, :text).to_s }.find { |text| text.start_with?(">") }

    assert_equal "> Block &lt;!channel&gt; probes  ·  <https://linear.app/firefight/issue/FIR-105|FIR-105>", body
  end

  test "an item typed by a person reads as it always has" do
    action = @incident.incident_actions.create!(created_by: @member, action_type: IncidentAction::ACTION_TYPE_ACTION, description: "Roll back *now*")

    assert_equal "Roll back *now*", Slack::Messages::Action.described(action)
  end

  test "an item offers Create issue while the workspace opens issues, and says why its issue is missing" do
    workspace = @incident.workspace
    linear = workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "linear", name: "Linear", slug: "linear", settings: {})
    linear.integration_environments.create!
    action = @incident.incident_actions.create!(created_by: @member, action_type: IncidentAction::ACTION_TYPE_FOLLOWUP, description: "Rotate")
    buttons = -> { Slack::Messages::Action.created(action.reload).find { |block| block[:type] == "actions" }[:elements].pluck(:action_id) }

    assert_not_includes buttons.call, Identifiers::CREATE_ACTION_ISSUE

    workspace.update!(issue_tracker: linear.slug, issue_creation: Workspace::IssueSync::ISSUE_CREATION_ASKED)
    assert_includes buttons.call, Identifiers::CREATE_ACTION_ISSUE

    action.update!(issue_sync_state: IncidentAction::ISSUE_FAILED, issue_sync_note: "Linear refused to open the issue: Team not found.")
    blocks = Slack::Messages::Action.created(action)
    assert(blocks.any? { |block| block[:type] == "context" && block[:elements].first[:text] == ":ticket: Linear refused to open the issue: Team not found." })
    assert_equal ":arrows_counterclockwise: Try the issue again", blocks.last[:elements].last.dig(:text, :text)
  end

  test "an item's message as it stands is the layout for its status" do
    action = @incident.incident_actions.create!(created_by: @member, action_type: IncidentAction::ACTION_TYPE_ACTION, description: "Roll back",
                                                assignee: @member, status: IncidentAction::STATUS_IN_PROGRESS)

    assert_equal Slack::Messages::Action.picked_up(action), Slack::Messages::Action.current(action)
    action.update!(status: IncidentAction::STATUS_DONE)
    assert_equal Slack::Messages::Action.completed(action), Slack::Messages::Action.current(action)
  end
end
