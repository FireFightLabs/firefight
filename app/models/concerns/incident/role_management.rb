# frozen_string_literal: true

# Incident::RoleManagement - Role assignment helpers
#
# Provides convenience methods for managing incident role assignments,
# with special helpers for the MVP "Incident Lead" role.
#
# Future: Can be extended to support multiple roles (Commander, Comms Lead, etc.)
#
module Incident::RoleManagement
  extend ActiveSupport::Concern

  # Role helper for MVP (returns the "Incident Lead" assignment)
  def lead
    lead_role = workspace.incident_roles.incident_lead
    incident_role_assignments.find_by(incident_role: lead_role)&.workspace_membership
  end

  def lead=(workspace_membership)
    lead_role = workspace.incident_roles.incident_lead
    return unless lead_role

    assignment = incident_role_assignments.find_or_initialize_by(incident_role: lead_role)
    assignment.workspace_membership = workspace_membership
    assignment.save!
  end
end
