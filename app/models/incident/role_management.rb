# Incident::RoleManagement - Role assignment helpers
#
# Provides convenience methods for managing incident role assignments,
# with special helpers for the MVP "Incident Lead" role.
#
# Future: Can be extended to support multiple roles (Commander, Comms Lead, etc.)
#
module Incident::RoleManagement
  extend ActiveSupport::Concern

  # Role helper for MVP (returns the "Incident Lead" assignment). Reads
  # don't materialize the role row — they just return nil when no
  # assignment exists.
  def lead
    lead_role = workspace.incident_roles.incident_lead.first
    return nil unless lead_role

    incident_role_assignments.find_by(incident_role: lead_role)&.workspace_membership
  end

  def lead=(workspace_membership)
    # Lazy-materialize the lead role on first assignment so workspaces never
    # need it seeded.
    lead_role = workspace.ensure_incident_role!(IncidentRole::SLUG_INCIDENT_LEAD)

    assignment = incident_role_assignments.find_or_initialize_by(incident_role: lead_role)
    assignment.workspace_membership = workspace_membership
    assignment.save!
  end
end
