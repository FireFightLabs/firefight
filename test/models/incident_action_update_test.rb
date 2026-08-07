require "test_helper"

class IncidentActionUpdateTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages, :incident_statuses, :incident_severities, :incident_actions, :incidents

  setup do
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:alice_workspace_one)
    @action = incident_actions(:inc1_action_open)
  end

  # ============================================================================
  # ASSOCIATIONS
  # ============================================================================

  test "has one incident_event as eventable" do
    action_update = create_action_update

    event = @incident.incident_events.create!(
      event_type: IncidentEvent::ACTION_CREATED,
      actor: @member,
      eventable: action_update
    )

    assert_instance_of IncidentActionUpdate, event.eventable
    assert_equal event, event.eventable.incident_event
  end

  test "belongs to incident_action" do
    update = create_action_update
    assert_equal @action, update.incident_action
  end

  test "belongs to incident" do
    update = create_action_update
    assert_equal @incident, update.incident
  end

  test "belongs to actor" do
    update = create_action_update
    assert_equal @member, update.actor
  end

  test "belongs to created_by" do
    update = create_action_update
    assert_equal @action.created_by, update.created_by
  end

  test "belongs to assignee (optional)" do
    update = create_action_update
    assert_equal @action.assignee, update.assignee

    update_no_assignee = create_action_update(assignee: nil)
    assert_nil update_no_assignee.assignee
  end

  # ============================================================================
  # VALIDATIONS
  # ============================================================================

  test "requires update_type" do
    update = IncidentActionUpdate.new(
      incident_action: @action, incident: @incident, actor: @member,
      created_by: @action.created_by, action_type: "action",
      description: @action.description, status: @action.status
    )
    assert_not update.valid?
    assert_includes update.errors[:update_type], "can't be blank"
  end

  test "update_type must be in UPDATE_TYPES" do
    update = IncidentActionUpdate.new(
      incident_action: @action, incident: @incident, update_type: "invalid",
      action_type: "action", actor: @member,
      created_by: @action.created_by,
      description: @action.description, status: @action.status
    )
    assert_not update.valid?
    assert_includes update.errors[:update_type], "is not included in the list"
  end

  test "requires action_type" do
    update = IncidentActionUpdate.new(
      incident_action: @action, incident: @incident,
      update_type: IncidentActionUpdate::CREATED,
      actor: @member, created_by: @action.created_by,
      description: @action.description, status: @action.status
    )
    assert_not update.valid?
    assert_includes update.errors[:action_type], "can't be blank"
  end

  test "action_type must be in ACTION_TYPES" do
    update = IncidentActionUpdate.new(
      incident_action: @action, incident: @incident,
      update_type: IncidentActionUpdate::CREATED,
      action_type: "invalid", actor: @member,
      created_by: @action.created_by,
      description: @action.description, status: @action.status
    )
    assert_not update.valid?
    assert_includes update.errors[:action_type], "is not included in the list"
  end

  test "requires description" do
    update = IncidentActionUpdate.new(
      incident_action: @action, incident: @incident,
      update_type: IncidentActionUpdate::CREATED,
      action_type: "action", actor: @member,
      created_by: @action.created_by, status: @action.status
    )
    assert_not update.valid?
    assert_includes update.errors[:description], "can't be blank"
  end

  test "requires status" do
    update = IncidentActionUpdate.new(
      incident_action: @action, incident: @incident,
      update_type: IncidentActionUpdate::CREATED,
      action_type: "action", actor: @member,
      created_by: @action.created_by, description: @action.description
    )
    assert_not update.valid?
    assert_includes update.errors[:status], "can't be blank"
  end

  test "status must be in STATUSES" do
    update = IncidentActionUpdate.new(
      incident_action: @action, incident: @incident,
      update_type: IncidentActionUpdate::CREATED,
      action_type: "action", actor: @member,
      created_by: @action.created_by,
      description: @action.description, status: "invalid"
    )
    assert_not update.valid?
    assert_includes update.errors[:status], "is not included in the list"
  end

  test "accepts all valid update_types" do
    IncidentActionUpdate::UPDATE_TYPES.each do |type|
      update = IncidentActionUpdate.new(
        incident_action: @action, incident: @incident,
        update_type: type, action_type: "action", actor: @member,
        created_by: @action.created_by,
        description: @action.description, status: @action.status
      )
      assert update.valid?, "#{type} should be valid"
    end
  end

  # ============================================================================
  # SCOPES
  # ============================================================================

  test "ordered scope orders by created_at ascending" do
    first = create_action_update(created_at: 2.hours.ago)
    second = create_action_update(update_type: IncidentActionUpdate::PICKED_UP, created_at: 1.hour.ago)

    updates = @action.incident_action_updates.ordered.to_a
    assert_equal first, updates.first
    assert_equal second, updates.last
  end

  test "by_type scope filters by update_type" do
    create_action_update
    create_action_update(update_type: IncidentActionUpdate::PICKED_UP)

    assert_equal 1, @action.incident_action_updates.by_type(IncidentActionUpdate::CREATED).count
    assert_equal 1, @action.incident_action_updates.by_type(IncidentActionUpdate::PICKED_UP).count
  end

  # ============================================================================
  # CONSTANTS
  # ============================================================================

  test "UPDATE_TYPES contains all types" do
    expected = %w[created picked_up completed reassigned]
    assert_equal expected.sort, IncidentActionUpdate::UPDATE_TYPES.sort
  end

  private

  def create_action_update(overrides = {})
    IncidentActionUpdate.create!({
      incident_action: @action,
      incident: @incident,
      update_type: IncidentActionUpdate::CREATED,
      action_type: @action.action_type,
      actor: @member,
      created_by: @action.created_by,
      assignee: @action.assignee,
      description: @action.description,
      status: @action.status
    }.merge(overrides))
  end
end
