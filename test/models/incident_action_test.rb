require "test_helper"

class IncidentActionTest < ActiveSupport::TestCase
  # Associations

  test "belongs to incident" do
    action = incident_actions(:inc1_action_open)
    assert_instance_of Incident, action.incident
    assert_equal incidents(:active_critical_ws1), action.incident
  end

  test "belongs to created_by workspace_membership" do
    action = incident_actions(:inc1_action_open)
    assert_instance_of WorkspaceMembership, action.created_by
    assert_equal workspace_memberships(:alice_workspace_one), action.created_by
  end

  test "belongs to assignee workspace_membership" do
    action = incident_actions(:inc1_action_open)
    assert_instance_of WorkspaceMembership, action.assignee
    assert_equal workspace_memberships(:bob_workspace_one), action.assignee
  end

  test "assignee is optional" do
    action = incident_actions(:inc1_followup)
    assert_nil action.assignee
    assert action.valid?
  end

  # Validations

  test "requires description" do
    action = IncidentAction.new(
      incident: incidents(:active_critical_ws1),
      created_by: workspace_memberships(:alice_workspace_one)
    )
    assert_not action.valid?
    assert_includes action.errors[:description], "can't be blank"
  end

  test "action_type must be in ACTION_TYPES" do
    action = IncidentAction.new(
      incident: incidents(:active_critical_ws1),
      created_by: workspace_memberships(:alice_workspace_one),
      description: "Test action",
      action_type: "invalid"
    )
    assert_not action.valid?
    assert_includes action.errors[:action_type], "is not included in the list"
  end

  test "status must be in STATUSES" do
    action = IncidentAction.new(
      incident: incidents(:active_critical_ws1),
      created_by: workspace_memberships(:alice_workspace_one),
      description: "Test action",
      status: "invalid"
    )
    assert_not action.valid?
    assert_includes action.errors[:status], "is not included in the list"
  end

  # Scopes

  test "active scope excludes soft-deleted actions" do
    active_actions = IncidentAction.active
    assert_not_includes active_actions, incident_actions(:inc1_deleted_action)
    assert_includes active_actions, incident_actions(:inc1_action_open)
  end

  test "actions scope returns only actions" do
    actions = IncidentAction.actions
    assert_includes actions, incident_actions(:inc1_action_open)
    assert_not_includes actions, incident_actions(:inc1_followup)
  end

  test "followups scope returns only followups" do
    followups = IncidentAction.followups
    assert_includes followups, incident_actions(:inc1_followup)
    assert_not_includes followups, incident_actions(:inc1_action_open)
  end

  test "open scope returns only open actions" do
    open_actions = IncidentAction.open
    assert_includes open_actions, incident_actions(:inc1_action_open)
    assert_not_includes open_actions, incident_actions(:inc2_action_done)
  end

  test "completed scope returns only done actions" do
    completed = IncidentAction.completed
    assert_includes completed, incident_actions(:inc2_action_done)
    assert_not_includes completed, incident_actions(:inc1_action_open)
  end

  test "recent scope orders by created_at descending" do
    actions = IncidentAction.recent.to_a
    created_times = actions.map(&:created_at)
    assert_equal created_times.sort.reverse, created_times
  end

  # Methods

  test "open? returns true for open status" do
    action = incident_actions(:inc1_action_open)
    assert action.open?
  end

  test "open? returns false for non-open status" do
    action = incident_actions(:inc2_action_done)
    assert_not action.open?
  end

  test "done? returns true for done status" do
    action = incident_actions(:inc2_action_done)
    assert action.done?
  end

  test "done? returns false for non-done status" do
    action = incident_actions(:inc1_action_open)
    assert_not action.done?
  end

  test "assigned? returns true when assignee present" do
    action = incident_actions(:inc1_action_open)
    assert action.assigned?
  end

  test "assigned? returns false when assignee nil" do
    action = incident_actions(:inc1_followup)
    assert_not action.assigned?
  end

  # Constants

  test "ACTION_TYPES constant contains action types" do
    assert_equal [ "action", "followup" ], IncidentAction::ACTION_TYPES
  end

  test "STATUSES constant contains all statuses" do
    assert_equal [ "open", "in_progress", "done" ], IncidentAction::STATUSES
  end

  test "action type constants are accessible" do
    assert_equal "action", IncidentAction::ACTION_TYPE_ACTION
    assert_equal "followup", IncidentAction::ACTION_TYPE_FOLLOWUP
  end

  test "status constants are accessible" do
    assert_equal "open", IncidentAction::STATUS_OPEN
    assert_equal "in_progress", IncidentAction::STATUS_IN_PROGRESS
    assert_equal "done", IncidentAction::STATUS_DONE
  end

  # Fixtures loading

  test "workspace one fixtures load correctly" do
    action = incident_actions(:inc1_action_open)
    assert_equal incidents(:active_critical_ws1), action.incident
    assert_equal "action", action.action_type
    assert_equal "open", action.status
    assert_equal "Increase database connection pool size", action.description
  end

  test "followup fixture loads correctly" do
    followup = incident_actions(:inc1_followup)
    assert_equal "followup", followup.action_type
    assert_nil followup.assignee
  end

  test "deleted action has deleted_at timestamp" do
    deleted = incident_actions(:inc1_deleted_action)
    assert_not_nil deleted.deleted_at
    assert deleted.deleted_at < Time.current
  end

  test "status and assignee cannot contradict each other" do
    incident = incidents(:active_critical_ws1)
    member = workspace_memberships(:alice_workspace_one)

    orphaned_progress = incident.incident_actions.new(
      created_by: member, action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: "x", status: IncidentAction::STATUS_IN_PROGRESS
    )
    assert_not orphaned_progress.valid?

    assigned_but_open = incident.incident_actions.new(
      created_by: member, assignee: member, action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: "x", status: IncidentAction::STATUS_OPEN
    )
    assert_not assigned_but_open.valid?

    done_unassigned = incident.incident_actions.new(
      created_by: member, action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: "x", status: IncidentAction::STATUS_DONE
    )
    assert done_unassigned.valid?, "done with nobody assigned is legitimate"
  end
end
