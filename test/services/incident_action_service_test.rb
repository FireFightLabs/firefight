require "test_helper"

class IncidentActionServiceTest < ActiveSupport::TestCase
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

    @service = IncidentActionService.new(@workspace)
  end

  test "create_action creates record and posts message" do
    stub_post_message

    action = @service.create_action(
      incident: @incident,
      created_by: @member,
      action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: "Restart the service"
    )

    assert_equal "action", action.action_type
    assert_equal "Restart the service", action.description
    assert_equal IncidentAction::STATUS_OPEN, action.status
    assert_equal @member, action.created_by
    assert_nil action.assignee
    assert_equal "1234567890.123456", action.message_ts
  end

  test "create_action with assignee" do
    stub_post_message

    action = @service.create_action(
      incident: @incident,
      created_by: @member,
      action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: "Check logs",
      assignee: @bob
    )

    assert_equal @bob, action.assignee
  end

  test "create_action creates followup type" do
    stub_post_message

    action = @service.create_action(
      incident: @incident,
      created_by: @member,
      action_type: IncidentAction::ACTION_TYPE_FOLLOWUP,
      description: "Add monitoring alerts"
    )

    assert_equal "followup", action.action_type
  end

  test "create_action creates incident event with action update" do
    stub_post_message

    assert_difference [ "IncidentEvent.count", "IncidentActionUpdate.count" ], 1 do
      @service.create_action(
        incident: @incident,
        created_by: @member,
        action_type: IncidentAction::ACTION_TYPE_ACTION,
        description: "Restart the service"
      )
    end

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::ACTION_CREATED)
    assert_equal @member, event.actor
    assert_instance_of IncidentActionUpdate, event.eventable

    action_update = event.eventable
    assert_equal IncidentActionUpdate::CREATED, action_update.update_type
    assert_equal "action", action_update.action_type
    assert_equal @incident, action_update.incident
    assert_equal @member, action_update.created_by
    assert_equal "Restart the service", action_update.description
    assert_equal IncidentAction::STATUS_OPEN, action_update.status
    assert_equal [], action_update.changed_fields
  end

  test "create_action stores platform_data" do
    stub_post_message

    action = @service.create_action(
      incident: @incident,
      created_by: @member,
      action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: "From reaction",
      platform_data: { source_message_link: "https://example.com/message" }
    )

    assert_equal "https://example.com/message", action.platform_data["source_message_link"]
  end

  test "pick_up_action assigns and updates status" do
    stub_post_message
    stub_update_message

    action = @service.create_action(
      incident: @incident,
      created_by: @member,
      action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: "Fix the issue"
    )

    @service.pick_up_action(action: action, picked_up_by: @bob)

    action.reload
    assert_equal @bob, action.assignee
    assert_equal IncidentAction::STATUS_IN_PROGRESS, action.status
  end

  test "pick_up_action creates incident event with action update" do
    stub_post_message
    stub_update_message

    action = @service.create_action(
      incident: @incident,
      created_by: @member,
      action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: "Fix the issue"
    )

    assert_difference [ "IncidentEvent.count", "IncidentActionUpdate.count" ], 1 do
      @service.pick_up_action(action: action, picked_up_by: @bob)
    end

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::ACTION_PICKED_UP)
    assert_equal @bob, event.actor
    assert_instance_of IncidentActionUpdate, event.eventable

    action_update = event.eventable
    assert_equal IncidentActionUpdate::PICKED_UP, action_update.update_type
    assert_equal @bob, action_update.assignee
    assert_equal IncidentAction::STATUS_IN_PROGRESS, action_update.status
    assert_includes action_update.changed_fields, "assignee"
    assert_includes action_update.changed_fields, "status"
  end

  test "complete_action sets done status" do
    stub_post_message
    stub_update_message

    action = @service.create_action(
      incident: @incident,
      created_by: @member,
      action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: "Fix the issue",
      assignee: @bob
    )

    @service.pick_up_action(action: action, picked_up_by: @bob)
    @service.complete_action(action: action, completed_by: @bob)

    action.reload
    assert_equal IncidentAction::STATUS_DONE, action.status
  end

  test "complete_action creates incident event with action update" do
    stub_post_message
    stub_update_message

    action = @service.create_action(
      incident: @incident,
      created_by: @member,
      action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: "Fix the issue",
      assignee: @bob
    )

    @service.pick_up_action(action: action, picked_up_by: @bob)

    assert_difference [ "IncidentEvent.count", "IncidentActionUpdate.count" ], 1 do
      @service.complete_action(action: action, completed_by: @bob)
    end

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::ACTION_COMPLETED)
    assert_equal @bob, event.actor
    assert_instance_of IncidentActionUpdate, event.eventable

    action_update = event.eventable
    assert_equal IncidentActionUpdate::COMPLETED, action_update.update_type
    assert_equal IncidentAction::STATUS_DONE, action_update.status
    assert_includes action_update.changed_fields, "status"
  end
end
