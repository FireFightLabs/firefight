require "test_helper"

class Interactions::MarkActionDoneHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_severities, :incident_statuses

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @severity = incident_severities(:critical_ws1)
    @status = incident_statuses(:investigating_ws1)

    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: @status,
      incident_severity: @severity,
      name: "Test incident",
      is_private: false,
      channel_id: "C_TEST_INCIDENT"
    )

    stub_post_message
    stub_update_message
    @action = IncidentActionService.new(@workspace).create_action(
      incident: @incident,
      created_by: @member,
      action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: "Fix the issue",
      assignee: @bob
    )
    IncidentActionService.new(@workspace).pick_up_action(action: @action, picked_up_by: @bob)
  end

  test "marks action as done" do
    stub_update_message

    result = Interactions::MarkActionDoneHandler.execute(build_interaction(@action.id))

    assert_nil result
    @action.reload
    assert_equal IncidentAction::STATUS_DONE, @action.status
  end

  test "creates incident event" do
    stub_update_message

    assert_difference -> { @incident.incident_events.count }, 1 do
      Interactions::MarkActionDoneHandler.execute(build_interaction(@action.id))
    end

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::ACTION_COMPLETED)
    assert_equal @bob, event.user
  end

  test "ignores already done action" do
    stub_update_message
    @action.update!(status: IncidentAction::STATUS_DONE)

    result = Interactions::MarkActionDoneHandler.execute(build_interaction(@action.id))

    assert_nil result
  end

  test "handles missing action silently" do
    result = Interactions::MarkActionDoneHandler.execute(build_interaction(SecureRandom.uuid))

    assert_nil result
  end

  private

  def build_interaction(action_id)
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::BLOCK_ACTIONS,
      team_id: @workspace.platform_id,
      user_id: @bob.platform_user_id,
      action_id: Identifiers::MARK_ACTION_DONE,
      action_value: action_id,
      trigger_id: "12345.trigger"
    )
  end
end
