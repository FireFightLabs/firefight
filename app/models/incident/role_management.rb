module Incident::RoleManagement
  extend ActiveSupport::Concern

  # A role names who is accountable, not who is working, so there is one holder
  # per role per incident and assigning replaces whoever held it. Parallel
  # effort is carried by actions and follow-ups, which are many by design.
  def role_holder(role)
    role_assignment_for(role)&.workspace_membership
  end

  # Both directions refuse on an incident that is over, because both announce.
  # Filling the lead DMs the person and rewrites the channel topic, and every
  # other role change posts to the channel, which may already be archived.
  def assign_role!(role, workspace_membership, assigned_by: nil)
    refuse_role_change!(role)

    assignment = incident_role_assignments.find_or_initialize_by(incident_role: role)
    assignment.workspace_membership = workspace_membership
    assignment.assigned_by = assigned_by
    assignment.save!
    assignment
  end

  def unassign_role!(role)
    refuse_role_change!(role)

    role_assignment_for(role)&.destroy
  end

  # Reads don't materialize the role row, they just return nil when no
  # assignment exists.
  def lead
    lead_role = workspace.incident_roles.incident_lead.first
    return nil unless lead_role

    role_holder(lead_role)
  end

  def lead=(workspace_membership)
    # Lazy-materialize the lead role on first assignment so workspaces never
    # need it seeded.
    assign_role!(workspace.ensure_incident_role!(IncidentRole::SLUG_INCIDENT_LEAD), workspace_membership)
  end

  private

  # Refuses rather than reports. A blocked reason a caller has to remember to
  # ask for is advisory, and forgetting to ask is how this reached the API and
  # MCP twice over.
  def refuse_role_change!(role)
    blocked_reason = role_assignment_blocked_reason(role)
    raise Incident::NotActive, blocked_reason if blocked_reason
  end

  def role_assignment_for(role)
    incident_role_assignments.find_by(incident_role: role)
  end
end
