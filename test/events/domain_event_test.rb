require "test_helper"

class DomainEventTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_severities, :incident_lifecycle_stages, :incident_statuses

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: incident_statuses(:investigating_ws1),
      incident_severity: incident_severities(:critical_ws1),
      name: "Test incident",
      is_private: false,
      source: Incident::SOURCE_SLACK
    )
    @occurred_at = Time.current
  end

  test "initializes with all attributes" do
    event = DomainEvent.new(
      event_type: IncidentEvent::INCIDENT_CREATED,
      incident_id: @incident.id,
      user_id: @member.id,
      data: { severity: "critical" },
      occurred_at: @occurred_at
    )

    assert_equal IncidentEvent::INCIDENT_CREATED, event.event_type
    assert_equal @incident.id, event.incident_id
    assert_equal @member.id, event.user_id
    assert_equal({ severity: "critical" }, event.data)
    assert_equal @occurred_at, event.occurred_at
  end

  test "initializes with nil user_id" do
    event = DomainEvent.new(
      event_type: IncidentEvent::INCIDENT_CREATED,
      incident_id: @incident.id,
      data: {},
      occurred_at: @occurred_at
    )

    assert_nil event.user_id
  end

  test "to_h serializes to hash" do
    event = DomainEvent.new(
      event_type: IncidentEvent::INCIDENT_CREATED,
      incident_id: @incident.id,
      user_id: @member.id,
      data: { "severity" => "critical" },
      occurred_at: @occurred_at
    )

    hash = event.to_h

    assert_equal IncidentEvent::INCIDENT_CREATED, hash["event_type"]
    assert_equal @incident.id, hash["incident_id"]
    assert_equal @member.id, hash["user_id"]
    assert_equal({ "severity" => "critical" }, hash["data"])
    assert_equal @occurred_at.iso8601(6), hash["occurred_at"]
  end

  test "from_h deserializes from hash" do
    hash = {
      "event_type" => IncidentEvent::INCIDENT_UPDATED,
      "incident_id" => @incident.id,
      "user_id" => @member.id,
      "data" => { "changed_fields" => [ "status" ] },
      "occurred_at" => @occurred_at.iso8601(6)
    }

    event = DomainEvent.from_h(hash)

    assert_equal IncidentEvent::INCIDENT_UPDATED, event.event_type
    assert_equal @incident.id, event.incident_id
    assert_equal @member.id, event.user_id
    assert_equal({ "changed_fields" => [ "status" ] }, event.data)
    assert_in_delta @occurred_at, event.occurred_at, 0.001
  end

  test "round-trip serialization preserves data" do
    original = DomainEvent.new(
      event_type: IncidentEvent::ACTION_CREATED,
      incident_id: @incident.id,
      user_id: @member.id,
      data: { "action_id" => "abc-123", "action_type" => "action" },
      occurred_at: @occurred_at
    )

    restored = DomainEvent.from_h(original.to_h)

    assert_equal original.event_type, restored.event_type
    assert_equal original.incident_id, restored.incident_id
    assert_equal original.user_id, restored.user_id
    assert_equal original.data, restored.data
    assert_in_delta original.occurred_at, restored.occurred_at, 0.001
  end

  test "from_h defaults data to empty hash when nil" do
    hash = {
      "event_type" => IncidentEvent::INCIDENT_CREATED,
      "incident_id" => @incident.id,
      "occurred_at" => @occurred_at.iso8601(6)
    }

    event = DomainEvent.from_h(hash)

    assert_equal({}, event.data)
  end

  test "lazy incident accessor loads record" do
    event = DomainEvent.new(
      event_type: IncidentEvent::INCIDENT_CREATED,
      incident_id: @incident.id,
      occurred_at: @occurred_at
    )

    assert_equal @incident, event.incident
  end

  test "lazy user accessor loads record" do
    event = DomainEvent.new(
      event_type: IncidentEvent::INCIDENT_CREATED,
      incident_id: @incident.id,
      user_id: @member.id,
      occurred_at: @occurred_at
    )

    assert_equal @member, event.user
  end

  test "lazy user accessor returns nil when user_id is nil" do
    event = DomainEvent.new(
      event_type: IncidentEvent::INCIDENT_CREATED,
      incident_id: @incident.id,
      occurred_at: @occurred_at
    )

    assert_nil event.user
  end
end
