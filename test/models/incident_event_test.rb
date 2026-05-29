require "test_helper"

class IncidentEventTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages, :incident_statuses, :incident_severities, :incidents, :incident_events, :incident_actions

  # ============================================================================
  # ASSOCIATIONS
  # ============================================================================

  test "belongs to incident" do
    event = incident_events(:inc1_created)
    assert_instance_of Incident, event.incident
    assert_equal incidents(:active_critical_ws1), event.incident
  end

  test "belongs to user workspace_membership" do
    event = incident_events(:inc1_created)
    assert_instance_of WorkspaceMembership, event.actor
    assert_equal workspace_memberships(:alice_workspace_one), event.actor
  end

  test "user is optional" do
    event = IncidentEvent.new(
      incident: incidents(:active_critical_ws1),
      event_type: IncidentEvent::MESSAGE_PINNED
    )
    assert_nil event.actor
    assert event.valid?
  end

  # ============================================================================
  # VALIDATIONS
  # ============================================================================

  test "requires event_type" do
    event = IncidentEvent.new(
      incident: incidents(:active_critical_ws1)
    )
    assert_not event.valid?
    assert_includes event.errors[:event_type], "can't be blank"
  end

  test "event_type must be in EVENT_TYPES" do
    event = IncidentEvent.new(
      incident: incidents(:active_critical_ws1),
      event_type: "invalid.type"
    )
    assert_not event.valid?
    assert_includes event.errors[:event_type], "is not included in the list"
  end

  test "accepts valid event_types when eventable presence matches the contract" do
    incident = incidents(:active_critical_ws1)
    member = workspace_memberships(:alice_workspace_one)
    snapshot_backed_types = IncidentEvent::UPDATE_TYPE_MAP.keys

    IncidentEvent::EVENT_TYPES.each do |event_type|
      event = IncidentEvent.new(incident: incident, event_type: event_type)

      if snapshot_backed_types.include?(event_type)
        event.eventable = IncidentUpdate.new(
          incident: incident,
          workspace_id: incident.workspace_id,
          incident_status: incident.incident_status,
          incident_severity: incident.incident_severity,
          declared_by: incident.declared_by,
          sequence_number: incident.sequence_number,
          identifier: incident.identifier,
          name: incident.name,
          is_private: incident.is_private,
          declared_at: incident.declared_at,
          update_type: IncidentEvent.update_type_for(event_type),
          created_by: member
        ) unless event_type.start_with?("action.") || event_type.start_with?("postmortem.")
      end

      next if event_type.start_with?("action.") || event_type.start_with?("postmortem.")
      assert event.valid?, "#{event_type} should be valid, got: #{event.errors.full_messages.join(', ')}"
    end
  end

  test "snapshot-backed event_type requires an eventable" do
    event = IncidentEvent.new(
      incident: incidents(:active_critical_ws1),
      event_type: IncidentEvent::INCIDENT_RESOLVED
    )
    assert_not event.valid?
    assert_includes event.errors[:eventable], "is required for event_type=#{IncidentEvent::INCIDENT_RESOLVED}"
  end

  test "action-only event_type rejects an eventable" do
    incident = incidents(:active_critical_ws1)
    member = workspace_memberships(:alice_workspace_one)

    update = IncidentUpdate.create!(
      incident: incident,
      workspace_id: incident.workspace_id,
      incident_status: incident.incident_status,
      incident_severity: incident.incident_severity,
      declared_by: incident.declared_by,
      sequence_number: incident.sequence_number,
      identifier: incident.identifier,
      name: incident.name,
      is_private: incident.is_private,
      declared_at: incident.declared_at,
      update_type: IncidentUpdate::UPDATED,
      created_by: member
    )

    event = IncidentEvent.new(
      incident: incident,
      event_type: IncidentEvent::MESSAGE_PINNED,
      eventable: update
    )
    assert_not event.valid?
    assert_includes event.errors[:eventable], "must be nil for event_type=#{IncidentEvent::MESSAGE_PINNED}"
  end

  # ============================================================================
  # SCOPES
  # ============================================================================

  test "chronological scope orders by created_at ascending" do
    events = IncidentEvent.chronological.to_a
    created_times = events.map(&:created_at)
    assert_equal created_times.sort, created_times
  end

  test "recent scope orders by created_at descending" do
    events = IncidentEvent.recent.to_a
    created_times = events.map(&:created_at)
    assert_equal created_times.sort.reverse, created_times
  end

  # ============================================================================
  # UPDATE_TYPE_MAP
  # ============================================================================

  test "update_type_for maps lifecycle event types to IncidentUpdate update_types" do
    assert_equal IncidentUpdate::CREATED, IncidentEvent.update_type_for(IncidentEvent::INCIDENT_CREATED)
    assert_equal IncidentUpdate::UPDATED, IncidentEvent.update_type_for(IncidentEvent::INCIDENT_UPDATED)
    assert_equal IncidentUpdate::CLOSED, IncidentEvent.update_type_for(IncidentEvent::INCIDENT_RESOLVED)
    assert_equal IncidentUpdate::REOPENED, IncidentEvent.update_type_for(IncidentEvent::INCIDENT_REOPENED)
  end

  test "update_type_for raises ArgumentError for events without an eventable" do
    assert_raises(ArgumentError) do
      IncidentEvent.update_type_for(IncidentEvent::MESSAGE_PINNED)
    end
  end

  # ============================================================================
  # CONSTANTS
  # ============================================================================

  test "EVENT_TYPES constant contains all event types" do
    expected_types = [
      "incident.created", "incident.updated", "incident.accepted", "lead.assigned",
      "action.created", "action.picked_up", "action.completed",
      "incident.escalated", "incident.resolved", "incident.reopened", "postmortem.generated", "postmortem.edited",
      "relationship.created", "incident.marked_duplicate", "incident.merged_into",
      "message.pinned", "message.unpinned", "message.file_shared",
      "incident.escalation_acknowledged", "incident.escalation_nudged"
    ]
    assert_equal expected_types.sort, IncidentEvent::EVENT_TYPES.sort
  end

  test "event type constants are accessible" do
    assert_equal "incident.created", IncidentEvent::INCIDENT_CREATED
    assert_equal "incident.updated", IncidentEvent::INCIDENT_UPDATED
    assert_equal "lead.assigned", IncidentEvent::LEAD_ASSIGNED
    assert_equal "incident.resolved", IncidentEvent::INCIDENT_RESOLVED
  end

  # ============================================================================
  # EVENT DESCRIPTIONS
  # ============================================================================

  test "description returns human-readable text for each event type" do
    IncidentEvent::EVENT_TYPES.each do |event_type|
      event = IncidentEvent.new(event_type: event_type)
      assert_not_nil event.description, "description should exist for #{event_type}"
      assert_kind_of String, event.description
    end
  end

  test "EVENT_DESCRIPTIONS covers all event types" do
    IncidentEvent::EVENT_TYPES.each do |event_type|
      assert IncidentEvent::EVENT_DESCRIPTIONS.key?(event_type),
        "EVENT_DESCRIPTIONS should include #{event_type}"
    end
  end

  # ============================================================================
  # DELEGATED TYPES + changed_fields
  # ============================================================================

  test "eventable is optional (action events carry only metadata)" do
    event = IncidentEvent.new(
      incident: incidents(:active_critical_ws1),
      event_type: IncidentEvent::MESSAGE_PINNED
    )
    assert_nil event.eventable
    assert event.valid?
  end

  test "updates scope returns events with IncidentUpdate eventable" do
    incident = incidents(:active_critical_ws1)
    member = workspace_memberships(:alice_workspace_one)

    update = IncidentUpdate.create!(
      incident: incident,
      workspace_id: incident.workspace_id,
      incident_status: incident.incident_status,
      incident_severity: incident.incident_severity,
      declared_by: incident.declared_by,
      sequence_number: incident.sequence_number,
      identifier: incident.identifier,
      name: incident.name,
      is_private: incident.is_private,
      declared_at: incident.declared_at,
      update_type: IncidentUpdate::UPDATED,
      created_by: member,
      changed_fields: [ "summary" ]
    )

    incident.incident_events.create!(
      event_type: IncidentEvent::INCIDENT_UPDATED,
      actor: member,
      eventable: update
    )

    assert_equal 1, incident.incident_events.updates.count
  end

  test "changed_fields delegates to IncidentActionUpdate when eventable" do
    incident = incidents(:active_critical_ws1)
    member = workspace_memberships(:alice_workspace_one)
    action = incident_actions(:inc1_action_open)

    action_update = IncidentActionUpdate.create!(
      incident_action: action,
      incident: incident,
      update_type: IncidentActionUpdate::PICKED_UP,
      action_type: action.action_type,
      actor: member,
      created_by: action.created_by,
      assignee: member,
      description: action.description,
      status: IncidentAction::STATUS_IN_PROGRESS,
      changed_fields: [ "assignee", "status" ]
    )

    event = incident.incident_events.create!(
      event_type: IncidentEvent::ACTION_PICKED_UP,
      actor: member,
      eventable: action_update
    )

    assert_equal [ "assignee", "status" ], event.changed_fields
    assert event.changed?(:status)
    assert_not event.changed?(:description)
  end

  test "changed_fields delegates to IncidentUpdate when eventable" do
    incident = incidents(:active_critical_ws1)
    member = workspace_memberships(:alice_workspace_one)

    update = IncidentUpdate.create!(
      incident: incident,
      workspace_id: incident.workspace_id,
      incident_status: incident.incident_status,
      incident_severity: incident.incident_severity,
      declared_by: incident.declared_by,
      sequence_number: incident.sequence_number,
      identifier: incident.identifier,
      name: incident.name,
      is_private: incident.is_private,
      declared_at: incident.declared_at,
      update_type: IncidentUpdate::UPDATED,
      created_by: member,
      changed_fields: [ "status", "severity" ]
    )

    event = incident.incident_events.create!(
      event_type: IncidentEvent::INCIDENT_UPDATED,
      actor: member,
      eventable: update
    )

    assert_equal [ "status", "severity" ], event.changed_fields
    assert event.changed?(:status)
    assert event.changed?(:severity)
    assert_not event.changed?(:name)
  end

  test "changed_fields returns empty array when no eventable" do
    event = incident_events(:inc1_lead_assigned)
    assert_equal [], event.changed_fields
  end

  # ============================================================================
  # FIXTURES LOADING
  # ============================================================================

  test "workspace one fixtures load correctly" do
    event = incident_events(:inc1_created)
    assert_equal incidents(:active_critical_ws1), event.incident
    assert_equal "incident.created", event.event_type
    assert_not_nil event.metadata
  end
end
