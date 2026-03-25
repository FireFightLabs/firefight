require "test_helper"

class IncidentUpdateTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages, :incident_statuses, :incident_severities, :incident_types, :incident_roles

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @status = incident_statuses(:investigating_ws1)
    @severity = incident_severities(:critical_ws1)

    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: @status,
      incident_severity: @severity,
      name: "Test incident",
      is_private: false,
      source: Incident::SOURCE_SLACK
    )
  end

  # ============================================================================
  # ASSOCIATIONS
  # ============================================================================

  test "has one incident_event as eventable" do
    update = create_update(update_type: IncidentUpdate::CREATED)

    event = @incident.incident_events.create!(
      event_type: IncidentEvent::INCIDENT_CREATED,
      user: @member,
      eventable: update
    )

    assert_instance_of IncidentUpdate, event.eventable
    assert_equal event, event.eventable.incident_event
  end

  test "belongs to incident" do
    update = create_update(update_type: IncidentUpdate::CREATED)
    assert_equal @incident, update.incident
  end

  test "belongs to incident_status" do
    update = create_update(update_type: IncidentUpdate::CREATED)
    assert_equal @status, update.incident_status
  end

  test "belongs to incident_severity" do
    update = create_update(update_type: IncidentUpdate::CREATED)
    assert_equal @severity, update.incident_severity
  end

  test "belongs to declared_by" do
    update = create_update(update_type: IncidentUpdate::CREATED)
    assert_equal @member, update.declared_by
  end

  test "lead is optional" do
    update = create_update(update_type: IncidentUpdate::CREATED, lead: nil)
    assert_nil update.lead
    assert update.valid?
  end

  test "created_by is optional" do
    update = create_update(update_type: IncidentUpdate::CREATED, created_by: nil)
    assert_nil update.created_by
    assert update.valid?
  end

  test "incident_type is optional" do
    update = create_update(update_type: IncidentUpdate::CREATED, incident_type: nil)
    assert_nil update.incident_type
    assert update.valid?
  end

  test "belongs to incident_type when present" do
    type = incident_types(:service_outage_ws1)
    update = create_update(update_type: IncidentUpdate::CREATED, incident_type: type)
    assert_equal type, update.incident_type
  end

  # ============================================================================
  # VALIDATIONS
  # ============================================================================

  test "requires update_type" do
    update = IncidentUpdate.new(**snapshot_attributes)
    assert_not update.valid?
    assert_includes update.errors[:update_type], "can't be blank"
  end

  test "update_type must be in UPDATE_TYPES" do
    update = IncidentUpdate.new(**snapshot_attributes, update_type: "invalid")
    assert_not update.valid?
    assert_includes update.errors[:update_type], "is not included in the list"
  end

  test "accepts all valid update_types" do
    IncidentUpdate::UPDATE_TYPES.each do |type|
      update = IncidentUpdate.new(**snapshot_attributes, update_type: type)
      assert update.valid?, "#{type} should be valid"
    end
  end

  # ============================================================================
  # SCOPES
  # ============================================================================

  test "ordered scope orders by created_at ascending" do
    first = create_update(update_type: IncidentUpdate::CREATED, created_at: 2.hours.ago)
    second = create_update(update_type: IncidentUpdate::UPDATED, created_at: 1.hour.ago)

    updates = @incident.incident_updates.ordered.to_a
    assert_equal first, updates.first
    assert_equal second, updates.last
  end

  test "communications scope returns updates with messages" do
    create_update(update_type: IncidentUpdate::CREATED)
    with_message = create_update(update_type: IncidentUpdate::UPDATED, message: "Root cause found")

    communications = @incident.incident_updates.communications.to_a
    assert_includes communications, with_message
    assert_equal 1, communications.size
  end

  test "by_type scope filters by update_type" do
    create_update(update_type: IncidentUpdate::CREATED)
    create_update(update_type: IncidentUpdate::UPDATED)

    assert_equal 1, @incident.incident_updates.by_type(IncidentUpdate::CREATED).count
    assert_equal 1, @incident.incident_updates.by_type(IncidentUpdate::UPDATED).count
  end

  # ============================================================================
  # CONSTANTS
  # ============================================================================

  test "UPDATE_TYPES contains all types" do
    expected = %w[created updated closed reopened lead_assigned]
    assert_equal expected.sort, IncidentUpdate::UPDATE_TYPES.sort
  end

  private

  def snapshot_attributes(overrides = {})
    {
      incident: @incident,
      workspace_id: @workspace.id,
      incident_status: @status,
      incident_severity: @severity,
      declared_by: @member,
      sequence_number: @incident.sequence_number,
      identifier: @incident.identifier,
      name: @incident.name,
      is_private: false,
      declared_at: @incident.declared_at,
      changed_fields: []
    }.merge(overrides)
  end

  def create_update(overrides = {})
    IncidentUpdate.create!(**snapshot_attributes.merge(overrides))
  end
end
