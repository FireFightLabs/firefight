require "test_helper"

class IncidentEventTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_statuses, :incident_severities, :incidents, :incident_events

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
      "incident.escalated", "incident.resolved", "incident.reopened", "postmortem.generated"
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
