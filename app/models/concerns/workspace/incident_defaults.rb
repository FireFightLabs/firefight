module Workspace::IncidentDefaults
  extend ActiveSupport::Concern

  DEFAULT_SEVERITIES = [
    { name: "Critical", slug: "critical", rank: 5, position: 1, is_default: false, color: "#DC143C", description: "Service-wide outage or data loss" },
    { name: "Major", slug: "major", rank: 3, position: 2, is_default: false, color: "#FF6B35", description: "Significant feature degradation" },
    { name: "Minor", slug: "minor", rank: 1, position: 3, is_default: true, color: "#FFA500", description: "Limited impact or workaround available" }
  ].freeze

  DEFAULT_STATUSES = [
    { name: "Triaging", slug: "triaging", stage: IncidentLifecycleStage::TRIAGE, position: 0, is_default: false, color: "#9B59B6", description: "Investigating a potential issue to confirm it is a real incident" },
    { name: "Investigating", slug: "investigating", stage: IncidentLifecycleStage::ACTIVE, position: 1, is_default: true, color: "#FFA500", description: "Root cause under active investigation" },
    { name: "Identified", slug: "identified", stage: IncidentLifecycleStage::ACTIVE, position: 2, is_default: false, color: "#FF6B35", description: "Root cause identified" },
    { name: "Monitoring", slug: "monitoring", stage: IncidentLifecycleStage::ACTIVE, position: 3, is_default: false, color: "#4169E1", description: "Fix deployed, monitoring for stability" },
    { name: "Resolved", slug: "resolved", stage: IncidentLifecycleStage::CLOSED, position: 4, is_default: false, color: "#32CD32", description: "Incident fully resolved" },
    { name: "Canceled", slug: "canceled", stage: IncidentLifecycleStage::CANCELED, position: 5, is_default: false, color: "#999999", description: "False positive, duplicate, or invalid incident" }
  ].freeze

  DEFAULT_TYPES = [
    { name: "Service Outage", slug: "service_outage", position: 1, is_default: false, description: "Service or infrastructure is down or unreachable." },
    { name: "Performance Degradation", slug: "performance_degradation", position: 2, is_default: false, description: "Elevated latency, errors, or capacity-related degradation." },
    { name: "Security Incident", slug: "security_incident", position: 3, is_default: false, description: "Unauthorized access, vulnerability exploitation, or data exposure risk." },
    { name: "Data Issue", slug: "data_issue", position: 4, is_default: false, description: "Data loss, corruption, integrity, or correctness issues." }
  ].freeze

  DEFAULT_ROLES = [
    { name: "Incident Lead", slug: IncidentRole::SLUG_INCIDENT_LEAD, position: 1, required: false, description: "Coordinates incident response and makes decisions" }
  ].freeze

  def setup_incident_configuration!
    transaction do
      create_default_severities!
      create_default_statuses!
      create_default_types!
      create_default_roles!
    end

    Rails.logger.info({
      event: "workspace.incident_configuration_created",
      message: "Created default incident configuration",
      workspace_id: id,
      severities_count: DEFAULT_SEVERITIES.count,
      statuses_count: DEFAULT_STATUSES.count,
      types_count: DEFAULT_TYPES.count,
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
      attrs = status_data.except(:stage)
      stage = IncidentLifecycleStage.find_by!(key: status_data[:stage])
      incident_statuses.create!(**attrs, incident_lifecycle_stage: stage)
    end
  end

  def create_default_types!
    DEFAULT_TYPES.each do |type_data|
      incident_types.create!(type_data)
    end
  end

  def create_default_roles!
    DEFAULT_ROLES.each do |role_data|
      incident_roles.create!(role_data)
    end
  end
end
