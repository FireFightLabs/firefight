require "test_helper"

class Interactions::PickUpActionHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_severities, :incident_lifecycle_stages, :incident_statuses

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
      channel_id: "C_TEST_INCIDENT",
      source: Incident::SOURCE_SLACK
    )

    stub_post_message
    @action = IncidentActionService.new(@workspace).create_action(
      incident: @incident,
      created_by: @member,
      action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: "Fix the issue"
    )
  end

  test "picks up unassigned action" do
    stub_update_message

    result = Interactions::PickUpActionHandler.execute(build_interaction(@action.id))

    assert_nil result
    @action.reload
    assert_equal @bob, @action.assignee
    assert_equal IncidentAction::STATUS_IN_PROGRESS, @action.status
  end

  test "creates incident event with action update" do
    stub_update_message

    assert_difference [ "IncidentEvent.count", "IncidentActionUpdate.count" ], 1 do
      Interactions::PickUpActionHandler.execute(build_interaction(@action.id))
    end

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::ACTION_PICKED_UP)
    assert_equal @bob, event.actor
    assert_instance_of IncidentActionUpdate, event.eventable
    assert_equal IncidentActionUpdate::PICKED_UP, event.eventable.update_type
  end

  test "ignores already assigned action" do
    stub_update_message
    @action.update!(assignee: @member, status: IncidentAction::STATUS_IN_PROGRESS)

    result = Interactions::PickUpActionHandler.execute(build_interaction(@action.id))

    assert_nil result
    @action.reload
    assert_equal @member, @action.assignee
  end

  test "handles missing action silently" do
    result = Interactions::PickUpActionHandler.execute(build_interaction(SecureRandom.uuid))

    assert_nil result
  end

  private

  def build_interaction(action_id)
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::BLOCK_ACTIONS,
      team_id: @workspace.platform_id,
      user_id: @bob.platform_user_id,
      action_id: Identifiers::PICK_UP_ACTION,
      action_value: action_id,
      trigger_id: "12345.trigger"
    )
  end
end
