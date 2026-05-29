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
      actor_type: "WorkspaceMembership",
      actor_id: @member.id,
      data: { severity: "critical" },
      occurred_at: @occurred_at
    )

    assert_equal IncidentEvent::INCIDENT_CREATED, event.event_type
    assert_equal @incident.id, event.incident_id
    assert_equal @member.id, event.actor_id
    assert_equal "WorkspaceMembership", event.actor_type
    assert_equal({ severity: "critical" }, event.data)
    assert_equal @occurred_at, event.occurred_at
  end

  test "initializes with nil actor" do
    event = DomainEvent.new(
      event_type: IncidentEvent::INCIDENT_CREATED,
      incident_id: @incident.id,
      data: {},
      occurred_at: @occurred_at
    )

    assert_nil event.actor_id
    assert_nil event.actor_type
  end

  test "to_h serializes to hash" do
    event = DomainEvent.new(
      event_type: IncidentEvent::INCIDENT_CREATED,
      incident_id: @incident.id,
      actor_type: "WorkspaceMembership",
      actor_id: @member.id,
      data: { "severity" => "critical" },
      occurred_at: @occurred_at
    )

    hash = event.to_h

    assert_equal IncidentEvent::INCIDENT_CREATED, hash["event_type"]
    assert_equal @incident.id, hash["incident_id"]
    assert_equal @member.id, hash["actor_id"]
    assert_equal "WorkspaceMembership", hash["actor_type"]
    assert_equal({ "severity" => "critical" }, hash["data"])
    assert_equal @occurred_at.iso8601(6), hash["occurred_at"]
  end

  test "from_h deserializes from hash" do
    hash = {
      "event_type" => IncidentEvent::INCIDENT_UPDATED,
      "incident_id" => @incident.id,
      "actor_type" => "WorkspaceMembership",
      "actor_id" => @member.id,
      "data" => { "changed_fields" => [ "status" ] },
      "occurred_at" => @occurred_at.iso8601(6)
    }

    event = DomainEvent.from_h(hash)

    assert_equal IncidentEvent::INCIDENT_UPDATED, event.event_type
    assert_equal @incident.id, event.incident_id
    assert_equal @member.id, event.actor_id
    assert_equal({ "changed_fields" => [ "status" ] }, event.data)
    assert_in_delta @occurred_at, event.occurred_at, 0.001
  end

  test "round-trip serialization preserves data" do
    original = DomainEvent.new(
      event_type: IncidentEvent::ACTION_CREATED,
      incident_id: @incident.id,
      actor_type: "WorkspaceMembership",
      actor_id: @member.id,
      data: { "action_id" => "abc-123", "action_type" => "action" },
      occurred_at: @occurred_at
    )

    restored = DomainEvent.from_h(original.to_h)

    assert_equal original.event_type, restored.event_type
    assert_equal original.incident_id, restored.incident_id
    assert_equal original.actor_id, restored.actor_id
    assert_equal original.actor_type, restored.actor_type
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

  test "lazy actor accessor loads record" do
    event = DomainEvent.new(
      event_type: IncidentEvent::INCIDENT_CREATED,
      incident_id: @incident.id,
      actor_type: "WorkspaceMembership",
      actor_id: @member.id,
      occurred_at: @occurred_at
    )

    assert_equal @member, event.actor
  end

  test "lazy actor accessor returns nil when actor is nil" do
    event = DomainEvent.new(
      event_type: IncidentEvent::INCIDENT_CREATED,
      incident_id: @incident.id,
      occurred_at: @occurred_at
    )

    assert_nil event.actor
  end

  test "actor resolves an ApiKey when actor_type is ApiKey" do
    api_key, = ApiKey.create_with_token!(
      workspace: @workspace,
      created_by: @member,
      name: "Datadog"
    )

    event = DomainEvent.new(
      event_type: IncidentEvent::INCIDENT_RESOLVED,
      incident_id: @incident.id,
      actor_type: "ApiKey",
      actor_id: api_key.id,
      occurred_at: @occurred_at
    )

    assert_equal api_key, event.actor
    assert_equal "Datadog", event.actor.actor_display_name
  end
end
