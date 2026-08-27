require "test_helper"

class IncidentAction::SnapshotsTest < ActiveSupport::TestCase
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

    @action = @incident.incident_actions.create!(
      created_by: @member,
      action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: "Fix the issue",
      status: IncidentAction::STATUS_OPEN
    )
  end

  test "snapshot_attributes returns all action columns" do
    attrs = @action.snapshot_attributes

    assert_equal @action, attrs[:incident_action]
    assert_equal @incident, attrs[:incident]
    assert_equal @member, attrs[:created_by]
    assert_nil attrs[:assignee]
    assert_equal "action", attrs[:action_type]
    assert_equal "Fix the issue", attrs[:description]
    assert_equal IncidentAction::STATUS_OPEN, attrs[:status]
    assert_nil attrs[:message_ts]
    assert_nil attrs[:deleted_at]
  end

  test "record_change! with no block records the initial creation snapshot" do
    assert_difference [ "IncidentActionUpdate.count", "IncidentEvent.count" ], 1 do
      @action.record_change!(IncidentEvent::ACTION_CREATED, by: @member)
    end

    update = @action.incident_action_updates.find_by!(update_type: IncidentActionUpdate::CREATED)
    assert_equal @incident, update.incident
    assert_equal @member, update.actor
    assert_equal @member, update.created_by
    assert_equal "Fix the issue", update.description
    assert_equal IncidentAction::STATUS_OPEN, update.status
    assert_equal "action", update.action_type
    assert_equal [], update.changed_fields

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::ACTION_CREATED)
    assert_equal update, event.eventable
    assert_equal @member, event.actor
  end

  test "record_change! captures changed fields" do
    @action.record_change!(IncidentEvent::ACTION_CREATED, by: @member)

    @action.record_change!(IncidentEvent::ACTION_PICKED_UP, by: @bob) do
      @action.update!(assignee: @bob, status: IncidentAction::STATUS_IN_PROGRESS)
    end

    update = @action.incident_action_updates.find_by!(update_type: IncidentActionUpdate::PICKED_UP)
    assert_equal @bob, update.assignee
    assert_equal IncidentAction::STATUS_IN_PROGRESS, update.status
    assert_includes update.changed_fields, "assignee"
    assert_includes update.changed_fields, "status"

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::ACTION_PICKED_UP)
    assert_equal update, event.eventable
    assert_equal @bob, event.actor
  end

  test "record_change! detects only actually changed fields" do
    @action.update!(assignee: @bob, status: IncidentAction::STATUS_IN_PROGRESS)
    @action.record_change!(IncidentEvent::ACTION_CREATED, by: @member)

    @action.record_change!(IncidentEvent::ACTION_COMPLETED, by: @bob) do
      @action.update!(status: IncidentAction::STATUS_DONE)
    end

    update = @action.incident_action_updates.find_by!(update_type: IncidentActionUpdate::COMPLETED)
    assert_equal [ "status" ], update.changed_fields
    assert_equal IncidentAction::STATUS_DONE, update.status
    assert_equal @bob, update.assignee
  end

  test "record_change! snapshot reflects state after change" do
    @action.record_change!(IncidentEvent::ACTION_CREATED, by: @member)

    @action.record_change!(IncidentEvent::ACTION_PICKED_UP, by: @bob) do
      @action.update!(assignee: @bob, status: IncidentAction::STATUS_IN_PROGRESS)
    end

    update = @action.incident_action_updates.find_by!(update_type: IncidentActionUpdate::PICKED_UP)
    assert_equal @bob, update.assignee
    assert_equal IncidentAction::STATUS_IN_PROGRESS, update.status
    assert_equal "Fix the issue", update.description
    assert_equal @member, update.created_by
  end

  test "message_ts written outside record_change! stays out of changed_fields" do
    IncidentAction.find(@action.id).update!(message_ts: "1234.5678")

    @action.record_change!(IncidentEvent::ACTION_PICKED_UP, by: @bob) do
      @action.update!(assignee: @bob, status: IncidentAction::STATUS_IN_PROGRESS)
    end

    update = @action.incident_action_updates.find_by!(update_type: IncidentActionUpdate::PICKED_UP)
    assert_equal %w[assignee status].sort, update.changed_fields.sort
    assert_equal "1234.5678", update.message_ts, "the snapshot still captures the current message_ts"
  end
end
