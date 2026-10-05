require "test_helper"

# Renaming, reopening and letting go of an item, the same on every surface since each calls these.
class IncidentActionEditsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @service = IncidentActionService.new(@workspace)
    stub_post_message
    stub_update_message
    stub_get_permalink
  end

  def item(**attributes)
    @incident.incident_actions.create!({ created_by: @alice, action_type: IncidentAction::ACTION_TYPE_ACTION, description: "Restart the worker",
                                         message_ts: "1700000000.000200" }.merge(attributes))
  end

  test "a rename records the change with its new title and redraws the item's message" do
    action = item
    Slack::WorkspaceAdapter.any_instance.expects(:refresh_action_message).with(has_entries(message_id: "1700000000.000200"))

    assert_nil @service.rename_action(action: action, description: "  Restart every worker ", renamed_by: @alice)

    assert_equal "Restart every worker", action.reload.description
    event = @incident.incident_events.find_by!(event_type: IncidentEvent::ACTION_RENAMED)
    assert_equal [ @alice, IncidentActionUpdate::RENAMED ], [ event.actor, event.eventable.update_type ]
  end

  test "a rename to nothing or to the same title is refused" do
    action = item

    assert_equal "Give the item a title.", @service.rename_action(action: action, description: " ", renamed_by: @alice)
    assert_equal "That is already its title.", @service.rename_action(action: action, description: "Restart the worker", renamed_by: @alice)
    assert_not @incident.incident_events.exists?(event_type: IncidentEvent::ACTION_RENAMED)
  end

  test "a done item reopens to whoever held it, or to open, and one that is not done is refused" do
    held = item(assignee: @alice, status: IncidentAction::STATUS_DONE)
    nobody = item(status: IncidentAction::STATUS_DONE)

    assert_nil @service.reopen_action(action: held, reopened_by: @alice)
    assert_nil @service.reopen_action(action: nobody, reopened_by: @alice)

    assert_equal [ IncidentAction::STATUS_IN_PROGRESS, @alice ], [ held.reload.status, held.assignee ]
    assert_equal IncidentAction::STATUS_OPEN, nobody.reload.status
    assert_equal "That item is not done.", @service.reopen_action(action: held, reopened_by: @alice)
  end

  test "an action on an incident that is over stays done, and a follow-up reopens" do
    over = incidents(:resolved_minor_ws1)
    action = over.incident_actions.create!(created_by: @alice, action_type: IncidentAction::ACTION_TYPE_ACTION, description: "x", status: IncidentAction::STATUS_DONE)
    follow_up = over.incident_actions.create!(created_by: @alice, action_type: IncidentAction::ACTION_TYPE_FOLLOWUP, description: "y", status: IncidentAction::STATUS_DONE)

    assert_match "its actions can no longer be reopened", @service.reopen_action(action: action, reopened_by: @alice)
    assert_nil @service.reopen_action(action: follow_up, reopened_by: @alice)
  end

  test "letting go leaves the item open with nobody, and is refused for one nobody holds or one that is done" do
    action = item(assignee: @alice, status: IncidentAction::STATUS_IN_PROGRESS)

    assert_nil @service.unassign_action(action: action, unassigned_by: @alice)

    assert_equal [ IncidentAction::STATUS_OPEN, nil ], [ action.reload.status, action.assignee ]
    assert_equal "Nobody holds that item.", @service.unassign_action(action: action, unassigned_by: @alice)
    assert_equal "That item is done. Reopen it first.", @service.unassign_action(action: item(status: IncidentAction::STATUS_DONE), unassigned_by: @alice)
  end

  test "two people reopening the same item at once reopen it once" do
    action = item(status: IncidentAction::STATUS_DONE)
    stale = IncidentAction.find(action.id)

    assert_nil @service.reopen_action(action: action, reopened_by: @alice)
    assert_equal "Someone changed that item first.", @service.reopen_action(action: stale, reopened_by: @alice)

    assert_equal 1, @incident.incident_events.where(event_type: IncidentEvent::ACTION_REOPENED).count
  end
end
