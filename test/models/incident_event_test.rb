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
    assert_instance_of WorkspaceMembership, event.user
    assert_equal workspace_memberships(:alice_workspace_one), event.user
  end

  test "user is optional" do
    event = IncidentEvent.new(
      incident: incidents(:active_critical_ws1),
      event_type: IncidentEvent::INCIDENT_UPDATED
    )
    assert_nil event.user
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

  test "accepts valid event_types" do
    IncidentEvent::EVENT_TYPES.each do |event_type|
      event = IncidentEvent.new(
        incident: incidents(:active_critical_ws1),
        event_type: event_type
      )
      assert event.valid?, "#{event_type} should be valid"
    end
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
  # HELPER METHODS
  # ============================================================================

  test "before_snapshot returns before metadata" do
    event = incident_events(:inc1_updated)
    snapshot = event.before_snapshot
    assert_equal "Database connection pool exhausted", snapshot["name"]
    assert_nil snapshot["summary"]
  end

  test "before_snapshot returns empty hash if not present" do
    event = incident_events(:inc1_created)
    assert_equal({}, event.before_snapshot)
  end

  test "after_snapshot returns after metadata" do
    event = incident_events(:inc1_created)
    snapshot = event.after_snapshot
    assert_equal "Database connection pool exhausted", snapshot["name"]
    assert_equal "investigating", snapshot["status"]
    assert_equal "critical", snapshot["severity"]
  end

  test "after_snapshot returns empty hash if not present" do
    event = incident_events(:inc1_lead_assigned)
    assert_equal({}, event.after_snapshot)
  end

  test "changed_fields returns list of changed fields" do
    event = incident_events(:inc1_updated)
    assert_equal [ "summary" ], event.changed_fields
  end

  test "changed_fields returns empty array if not present" do
    event = incident_events(:inc1_created)
    assert_equal [], event.changed_fields
  end

  test "details returns details metadata" do
    event = incident_events(:inc1_lead_assigned)
    details = event.details
    assert_equal "incident_lead", details["role"]
    assert_equal "alice_workspace_one", details["assigned_to"]
  end

  test "details returns nil if not present" do
    event = incident_events(:inc1_created)
    assert_nil event.details
  end

  test "changed? returns true for changed fields" do
    event = incident_events(:inc1_updated)
    assert event.changed?("summary")
    assert event.changed?(:summary)
  end

  test "changed? returns false for unchanged fields" do
    event = incident_events(:inc1_updated)
    assert_not event.changed?("name")
    assert_not event.changed?(:status)
  end

  # ============================================================================
  # CONSTANTS
  # ============================================================================

  test "EVENT_TYPES constant contains all event types" do
    expected_types = [
      "incident.created", "incident.updated", "lead.assigned",
      "action.created", "action.picked_up", "action.completed",
      "incident.escalated", "incident.resolved", "incident.reopened", "postmortem.generated",
      "relationship.created", "incident.marked_duplicate", "incident.merged_into",
      "message.pinned", "message.unpinned", "message.file_shared"
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
  # DOMAIN EVENT BUS
  # ============================================================================

  test "enqueues ProcessDomainEventJob after create" do
    incident = incidents(:active_critical_ws1)
    member = workspace_memberships(:alice_workspace_one)

    ProcessDomainEventJob.expects(:perform_later).with { |hash|
      hash["event_type"] == IncidentEvent::INCIDENT_UPDATED &&
        hash["incident_id"] == incident.id &&
        hash["user_id"] == member.id
    }

    IncidentEvent.create!(
      incident: incident,
      event_type: IncidentEvent::INCIDENT_UPDATED,
      user: member,
      metadata: { "changed_fields" => [ "summary" ] }
    )
  end

  test "enqueued job receives correct event data" do
    incident = incidents(:active_critical_ws1)
    member = workspace_memberships(:alice_workspace_one)

    ProcessDomainEventJob.expects(:perform_later).with { |hash|
      hash["event_type"] == IncidentEvent::ACTION_CREATED &&
        hash["incident_id"] == incident.id &&
        hash["user_id"] == member.id &&
        hash["data"] == { "action_id" => "test-123" } &&
        hash["occurred_at"].present?
    }

    IncidentEvent.create!(
      incident: incident,
      event_type: IncidentEvent::ACTION_CREATED,
      user: member,
      metadata: { "action_id" => "test-123" }
    )
  end

  # ============================================================================
  # DELEGATED TYPES
  # ============================================================================

  test "delegated_type is optional" do
    event = IncidentEvent.new(
      incident: incidents(:active_critical_ws1),
      event_type: IncidentEvent::INCIDENT_UPDATED
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
      user: member,
      eventable: update
    )

    assert_equal 1, incident.incident_events.updates.count
  end

  test "action_updates scope returns events with IncidentActionUpdate eventable" do
    incident = incidents(:active_critical_ws1)
    member = workspace_memberships(:alice_workspace_one)
    action = incident_actions(:inc1_action_open)

    action_update = IncidentActionUpdate.create!(
      incident_action: action,
      incident: incident,
      update_type: IncidentActionUpdate::CREATED,
      action_type: action.action_type,
      actor: member,
      created_by: action.created_by,
      assignee: action.assignee,
      description: action.description,
      status: action.status
    )

    incident.incident_events.create!(
      event_type: IncidentEvent::ACTION_CREATED,
      user: member,
      eventable: action_update
    )

    assert_equal 1, incident.incident_events.action_updates.count
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
      user: member,
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
      user: member,
      eventable: update
    )

    assert_equal [ "status", "severity" ], event.changed_fields
    assert event.changed?(:status)
    assert event.changed?(:severity)
    assert_not event.changed?(:name)
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

  test "event with changed_fields loads correctly" do
    event = incident_events(:inc1_updated)
    assert_equal [ "summary" ], event.changed_fields
    assert event.changed?("summary")
  end

  test "event with details loads correctly" do
    event = incident_events(:inc3_resolved)
    assert_equal 4, event.details["resolution_time"]
    assert_equal "Fixed by restarting upload service", event.details["resolution_notes"]
  end
end
