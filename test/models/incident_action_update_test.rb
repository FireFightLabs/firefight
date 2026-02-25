require "test_helper"

class IncidentActionUpdateTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_statuses, :incident_severities, :incident_actions, :incidents

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
      user: @member,
      eventable: action_update
    )

    assert_instance_of IncidentActionUpdate, event.eventable
    assert_equal event, event.eventable.incident_event
  end

  test "belongs to incident_action" do
    update = create_action_update
    assert_equal @action, update.incident_action
  end

  test "belongs to actor" do
    update = create_action_update
    assert_equal @member, update.actor
  end

  # ============================================================================
  # VALIDATIONS
  # ============================================================================

  test "requires action_update_type" do
    update = IncidentActionUpdate.new(incident_action: @action, action_type: "action", actor: @member)
    assert_not update.valid?
    assert_includes update.errors[:action_update_type], "can't be blank"
  end

  test "action_update_type must be in ACTION_UPDATE_TYPES" do
    update = IncidentActionUpdate.new(
      incident_action: @action, action_update_type: "invalid",
      action_type: "action", actor: @member
    )
    assert_not update.valid?
    assert_includes update.errors[:action_update_type], "is not included in the list"
  end

  test "requires action_type" do
    update = IncidentActionUpdate.new(
      incident_action: @action, action_update_type: IncidentActionUpdate::CREATED,
      actor: @member
    )
    assert_not update.valid?
    assert_includes update.errors[:action_type], "can't be blank"
  end

  test "action_type must be in ACTION_TYPES" do
    update = IncidentActionUpdate.new(
      incident_action: @action, action_update_type: IncidentActionUpdate::CREATED,
      action_type: "invalid", actor: @member
    )
    assert_not update.valid?
    assert_includes update.errors[:action_type], "is not included in the list"
  end

  test "accepts all valid action_update_types" do
    IncidentActionUpdate::ACTION_UPDATE_TYPES.each do |type|
      update = IncidentActionUpdate.new(
        incident_action: @action, action_update_type: type,
        action_type: "action", actor: @member
      )
      assert update.valid?, "#{type} should be valid"
    end
  end

  # ============================================================================
  # SCOPES
  # ============================================================================

  test "ordered scope orders by created_at ascending" do
    first = create_action_update(created_at: 2.hours.ago)
    second = create_action_update(action_update_type: IncidentActionUpdate::PICKED_UP, created_at: 1.hour.ago)

    updates = @action.incident_action_updates.ordered.to_a
    assert_equal first, updates.first
    assert_equal second, updates.last
  end

  # ============================================================================
  # CONSTANTS
  # ============================================================================

  test "ACTION_UPDATE_TYPES contains all types" do
    expected = %w[created picked_up completed]
    assert_equal expected.sort, IncidentActionUpdate::ACTION_UPDATE_TYPES.sort
  end

  private

  def create_action_update(overrides = {})
    IncidentActionUpdate.create!({
      incident_action: @action,
      action_update_type: IncidentActionUpdate::CREATED,
      action_type: @action.action_type,
      actor: @member
    }.merge(overrides))
  end
end
