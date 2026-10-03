module Workspace::IncidentDefaults
  extend ActiveSupport::Concern

  DEFAULT_SEVERITIES = [
    { name: "Critical", slug: IncidentSeverity::SLUG_CRITICAL, rank: 5, position: 1, is_default: false, color: "#F05653", description: "Service-wide outage or data loss." },
    { name: "Major", slug: "major", rank: 3, position: 2, is_default: false, color: "#F18336", description: "Significant feature degradation." },
    { name: "Minor", slug: "minor", rank: 1, position: 3, is_default: true, color: "#EFD369", description: "Limited impact or workaround available." }
  ].freeze

  DEFAULT_STATUSES = [
    { name: "Triaging", slug: IncidentStatus::SLUG_TRIAGING, stage: IncidentLifecycleStage::TRIAGE, position: 0, is_default: false, color: "#A98AEA", description: "Investigating a potential issue to confirm it is a real incident." },
    { name: "Investigating", slug: IncidentStatus::SLUG_INVESTIGATING, stage: IncidentLifecycleStage::ACTIVE, position: 1, is_default: true, color: "#70D5ED", description: "Root cause under active investigation." },
    { name: "Identified", slug: IncidentStatus::SLUG_IDENTIFIED, stage: IncidentLifecycleStage::ACTIVE, position: 2, is_default: false, color: "#70D5ED", description: "Root cause identified." },
    { name: "Monitoring", slug: IncidentStatus::SLUG_MONITORING, stage: IncidentLifecycleStage::ACTIVE, position: 3, is_default: false, color: "#70D5ED", description: "Fix deployed, monitoring for stability." },
    { name: "Resolved", slug: IncidentStatus::SLUG_RESOLVED, stage: IncidentLifecycleStage::CLOSED, position: 4, is_default: false, color: "#9EE464", description: "Incident fully resolved." },
    { name: "Canceled", slug: IncidentStatus::SLUG_CANCELED, stage: IncidentLifecycleStage::CANCELED, position: 5, is_default: false, color: "#9D9F9D", description: "False positive, duplicate, or invalid incident." }
  ].freeze

  DEFAULT_TYPES = [
    { name: "Production", slug: "production", position: 1, color: "#9EE464", description: "Customer-facing service disruption or degradation." },
    { name: "Security", slug: "security", position: 2, color: "#70D5ED", description: "Unauthorized access, data exposure, or vulnerability exploitation." },
    { name: "Infrastructure", slug: "infrastructure", position: 3, color: "#A98AEA", description: "Cloud, network, or platform-level failures." },
    { name: "Data", slug: "data", position: 4, color: "#F18336", description: "Data loss, corruption, pipeline failure, or integrity issues." },
    { name: "Third Party", slug: "third_party", position: 5, color: "#9D9F9D", description: "Vendor or external dependency outage affecting your systems." }
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
      types_count: DEFAULT_TYPES.count
    })
  end

  # Older migrations call it. Forms need no per-workspace rows any more.
  def setup_incident_forms!
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

  def create_default_roles!
    IncidentRole::DEFAULTS.each { |attrs| incident_roles.create!(attrs) }
  end

  def create_default_types!
    DEFAULT_TYPES.each do |type_data|
      incident_types.create!(type_data)
    end
  end

  def create_default_forms!
    DEFAULT_FORMS.each do |form_data|
      form = incident_forms.find_or_initialize_by(slug: form_data[:slug])
      form.assign_attributes(form_data)
      form.save!
    end
  end
end
