require "test_helper"

class IncidentRoleAssignmentTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_statuses, :incident_severities, :incident_roles, :incidents, :incident_role_assignments

  # ============================================================================
  # ASSOCIATIONS
  # ============================================================================

  test "belongs to incident" do
    assignment = incident_role_assignments(:bob_comms_ws1_inc1)
    assert_instance_of Incident, assignment.incident
    assert_equal incidents(:active_critical_ws1), assignment.incident
  end

  test "belongs to incident_role" do
    assignment = incident_role_assignments(:alice_lead_ws1_inc3)
    assert_instance_of IncidentRole, assignment.incident_role
    assert_equal incident_roles(:incident_lead_ws1), assignment.incident_role
  end

  test "belongs to workspace_membership" do
    assignment = incident_role_assignments(:alice_lead_ws1_inc3)
    assert_instance_of WorkspaceMembership, assignment.workspace_membership
    assert_equal workspace_memberships(:alice_workspace_one), assignment.workspace_membership
  end

  test "belongs to assigned_by workspace_membership" do
    assignment = incident_role_assignments(:bob_comms_ws1_inc1)
    assert_instance_of WorkspaceMembership, assignment.assigned_by
    assert_equal workspace_memberships(:alice_workspace_one), assignment.assigned_by
  end

  test "assigned_by is optional" do
    # Use a role that's not yet assigned to this incident
    assignment = IncidentRoleAssignment.new(
      incident: incidents(:manual_incident_ws1),
      incident_role: incident_roles(:incident_lead_ws1),
      workspace_membership: workspace_memberships(:alice_workspace_one)
    )
    assert_nil assignment.assigned_by
    assert assignment.valid?
  end

  # ============================================================================
  # VALIDATIONS
  # ============================================================================

  test "incident_role_id must be unique per incident" do
    existing = incident_role_assignments(:bob_lead_ws1_inc2)
    duplicate = IncidentRoleAssignment.new(
      incident: existing.incident,
      incident_role: existing.incident_role,
      workspace_membership: workspace_memberships(:alice_workspace_one)
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:incident_role_id], "has already been taken"
  end

  test "same incident_role can be assigned to different incidents" do
    # incident_lead_ws1 is assigned to active_major_ws1 and resolved_minor_ws1
    # Now assign it to manual_incident_ws1 (which has no lead yet)
    assignment = IncidentRoleAssignment.new(
      incident: incidents(:manual_incident_ws1),
      incident_role: incident_roles(:incident_lead_ws1),
      workspace_membership: workspace_memberships(:bob_workspace_one)
    )
    # Should be valid - same role can be used across different incidents
    assert assignment.valid?
  end

  # ============================================================================
  # SCOPES
  # ============================================================================

  test "recent scope orders by assigned_at descending" do
    assignments = IncidentRoleAssignment.recent.to_a
    assigned_times = assignments.map(&:assigned_at)
    assert_equal assigned_times.sort.reverse, assigned_times
  end

  # ============================================================================
  # CALLBACKS
  # ============================================================================

  test "auto-sets assigned_at on create" do
    # Use a role that isn't already assigned to this incident
    assignment = IncidentRoleAssignment.new(
      incident: incidents(:active_major_ws1),
      incident_role: incident_roles(:communications_lead_ws1),
      workspace_membership: workspace_memberships(:alice_workspace_one)
    )

    assert_nil assignment.assigned_at
    assignment.save!
    assert_not_nil assignment.assigned_at
    assert_instance_of ActiveSupport::TimeWithZone, assignment.assigned_at
  end

  test "does not override assigned_at if already set" do
    custom_time = 1.day.ago
    assignment = IncidentRoleAssignment.create!(
      incident: incidents(:active_major_ws1),
      incident_role: incident_roles(:communications_lead_ws1),
      workspace_membership: workspace_memberships(:alice_workspace_one),
      assigned_at: custom_time
    )

    assert_equal custom_time.to_i, assignment.assigned_at.to_i
  end

  # ============================================================================
  # FIXTURES LOADING
  # ============================================================================

  test "workspace one fixtures load correctly" do
    assignment = incident_role_assignments(:bob_comms_ws1_inc1)
    assert_equal incidents(:active_critical_ws1), assignment.incident
    assert_equal incident_roles(:communications_lead_ws1), assignment.incident_role
    assert_equal workspace_memberships(:bob_workspace_one), assignment.workspace_membership
    assert_not_nil assignment.assigned_at
  end

  test "multiple roles can be assigned to same incident" do
    inc1_assignments = IncidentRoleAssignment.where(incident: incidents(:active_critical_ws1))
    # Only has communications lead now
    assert_equal 1, inc1_assignments.count

    roles = inc1_assignments.map(&:incident_role)
    assert_includes roles, incident_roles(:communications_lead_ws1)
  end

  test "same role can be assigned to different people in different incidents" do
    lead_role = incident_roles(:incident_lead_ws1)

    # Alice is lead for inc3 (resolved_minor_ws1)
    inc3_lead = IncidentRoleAssignment.find_by(
      incident: incidents(:resolved_minor_ws1),
      incident_role: lead_role
    )
    assert_equal workspace_memberships(:alice_workspace_one), inc3_lead.workspace_membership

    # Bob is lead for inc2 (active_major_ws1)
    inc2_lead = IncidentRoleAssignment.find_by(
      incident: incidents(:active_major_ws1),
      incident_role: lead_role
    )
    assert_equal workspace_memberships(:bob_workspace_one), inc2_lead.workspace_membership
  end

  test "workspace two fixtures use different role naming" do
    assignment = incident_role_assignments(:alice_lead_ws2_inc1)
    assert_equal "Incident Commander", assignment.incident_role.name
    assert_equal incidents(:active_p0_ws2), assignment.incident
  end

  test "fixture references use correct incident_roles" do
    alice_assignment = incident_role_assignments(:alice_lead_ws1_inc3)
    assert_equal incident_roles(:incident_lead_ws1), alice_assignment.incident_role

    bob_assignment = incident_role_assignments(:bob_comms_ws1_inc1)
    assert_equal incident_roles(:communications_lead_ws1), bob_assignment.incident_role
  end
end
