# frozen_string_literal: true

# Workspace::IncidentDefaults - Default incident configuration
#
# Provides default statuses, severities, and roles seeded on workspace creation.
# These can be customized per workspace after initial setup.
#
module Workspace::IncidentDefaults
  extend ActiveSupport::Concern

  # Default severities (customize per workspace later)
  DEFAULT_SEVERITIES = [
    { name: "Critical", slug: "critical", rank: 5, position: 1, is_default: false, color: "#DC143C", description: "Service-wide outage or data loss" },
    { name: "Major", slug: "major", rank: 3, position: 2, is_default: false, color: "#FF6B35", description: "Significant feature degradation" },
    { name: "Minor", slug: "minor", rank: 1, position: 3, is_default: true, color: "#FFA500", description: "Limited impact or workaround available" }
  ].freeze

  # Default statuses (live vs closed categories)
  DEFAULT_STATUSES = [
    # Live statuses (active incident work)
    { name: "Investigating", slug: "investigating", category: IncidentStatus::CATEGORY_LIVE, position: 1, is_default: true, color: "#FFA500", description: "Initial triage and investigation" },
    { name: "Identified", slug: "identified", category: IncidentStatus::CATEGORY_LIVE, position: 2, is_default: false, color: "#FF6B35", description: "Root cause identified" },
    { name: "Monitoring", slug: "monitoring", category: IncidentStatus::CATEGORY_LIVE, position: 3, is_default: false, color: "#4169E1", description: "Fix deployed, monitoring for stability" },

    # Closed statuses (post-incident learning)
    { name: "Resolved", slug: "resolved", category: IncidentStatus::CATEGORY_CLOSED, position: 4, is_default: false, color: "#32CD32", description: "Incident fully resolved" }
  ].freeze

  # Default roles (MVP: one role, extendable later)
  DEFAULT_ROLES = [
    { name: "Incident Lead", slug: "incident_lead", position: 1, required: false, description: "Coordinates incident response and makes decisions" }
  ].freeze

  def setup_incident_configuration!
    transaction do
      create_default_severities!
      create_default_statuses!
      create_default_roles!
    end

    Rails.logger.info({
      event: "workspace.incident_configuration_created",
      message: "Created default incident configuration",
      workspace_id: id,
      severities_count: DEFAULT_SEVERITIES.count,
      statuses_count: DEFAULT_STATUSES.count,
      roles_count: DEFAULT_ROLES.count
    })
  end

  private

  def create_default_severities!
    DEFAULT_SEVERITIES.each do |severity_data|
      incident_severities.create!(severity_data)
    end
  end

  def create_default_statuses!
    DEFAULT_STATUSES.each do |status_data|
      incident_statuses.create!(status_data)
    end
  end

  def create_default_roles!
    DEFAULT_ROLES.each do |role_data|
      incident_roles.create!(role_data)
    end
  end
end
