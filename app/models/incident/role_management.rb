module Incident::RoleManagement
  extend ActiveSupport::Concern

  # One holder per role per incident, assigning replaces whoever held it.
  # A seat nobody holds is still listed, or there is no way to fill it.
  RoleSeat = Data.define(:incident_role, :workspace_membership)

  def role_roster
    holders = incident_role_assignments.includes(:workspace_membership).index_by(&:incident_role_id)

    workspace.incident_roles.active.ordered.filter_map do |role|
      next if role.slug == IncidentRole::SLUG_INCIDENT_LEAD

      RoleSeat.new(incident_role: role, workspace_membership: holders[role.id]&.workspace_membership)
    end
  end

  def role_holder(role)
    role_assignment_for(role)&.workspace_membership
  end

  # Refused on an incident that is over because every role change announces
  # itself in a channel that may already be archived.
  def assign_role!(role, workspace_membership, assigned_by: nil)
    refuse_role_change!(role)

    assignment = incident_role_assignments.find_or_initialize_by(incident_role: role)
    assignment.workspace_membership = workspace_membership
    assignment.assigned_by = assigned_by
    assignment.save!
    incident_role_assignments.reset
    assignment
  end

  def unassign_role!(role)
    refuse_role_change!(role)

    role_assignment_for(role)&.destroy
    incident_role_assignments.reset
  end

  # Read off the loaded assignments when preloaded, one joined query otherwise.
  def lead
    lead_assignment&.workspace_membership
  end

  def lead_assignment
    if incident_role_assignments.loaded?
      incident_role_assignments.detect { |assignment| assignment.incident_role.slug == IncidentRole::SLUG_INCIDENT_LEAD }
    else
      incident_role_assignments.joins(:incident_role).find_by(incident_roles: { slug: IncidentRole::SLUG_INCIDENT_LEAD })
    end
  end

  def lead=(workspace_membership)
    # Created on first assignment so workspaces never need it seeded.
    assign_role!(workspace.ensure_incident_role!(IncidentRole::SLUG_INCIDENT_LEAD), workspace_membership)
  end

  private

  # Raises rather than returning a reason. Forgetting to ask for a reason is
  # how this reached the API and MCP twice.
  def refuse_role_change!(role)
    blocked_reason = role_assignment_blocked_reason(role)
    raise Incident::NotActive, blocked_reason if blocked_reason
  end

  def role_assignment_for(role)
    if incident_role_assignments.loaded?
      incident_role_assignments.detect { |assignment| assignment.incident_role_id == role.id }
    else
      incident_role_assignments.find_by(incident_role: role)
    end
  end
end
