module Workspace::IncidentDefaults
  extend ActiveSupport::Concern

  DEFAULT_SEVERITIES = [
    { name: "Critical", slug: IncidentSeverity::SLUG_CRITICAL, rank: 5, position: 1, is_default: false, color: "#D42B2B", description: "Service-wide outage or data loss" },
    { name: "Major", slug: "major", rank: 3, position: 2, is_default: false, color: "#E07A12", description: "Significant feature degradation" },
    { name: "Minor", slug: "minor", rank: 1, position: 3, is_default: true, color: "#3B82F6", description: "Limited impact or workaround available" }
  ].freeze

  DEFAULT_STATUSES = [
    { name: "Triaging", slug: "triaging", stage: IncidentLifecycleStage::TRIAGE, position: 0, is_default: false, color: "#8B5CF6", description: "Investigating a potential issue to confirm it is a real incident" },
    { name: "Investigating", slug: "investigating", stage: IncidentLifecycleStage::ACTIVE, position: 1, is_default: true, color: "#38BDF8", description: "Root cause under active investigation" },
    { name: "Identified", slug: "identified", stage: IncidentLifecycleStage::ACTIVE, position: 2, is_default: false, color: "#14B8A6", description: "Root cause identified" },
    { name: "Monitoring", slug: "monitoring", stage: IncidentLifecycleStage::ACTIVE, position: 3, is_default: false, color: "#22C55E", description: "Fix deployed, monitoring for stability" },
    { name: "Resolved", slug: "resolved", stage: IncidentLifecycleStage::CLOSED, position: 4, is_default: false, color: "#16A34A", description: "Incident fully resolved" },
    { name: "Canceled", slug: "canceled", stage: IncidentLifecycleStage::CANCELED, position: 5, is_default: false, color: "#6B7280", description: "False positive, duplicate, or invalid incident" }
  ].freeze

  DEFAULT_TYPES = [
    { name: "Production", slug: "production", position: 1, is_default: true, color: "#DC143C", description: "Customer-facing service disruption or degradation." },
    { name: "Security", slug: "security", position: 2, is_default: false, color: "#8B5CF6", description: "Unauthorized access, data exposure, or vulnerability exploitation." },
    { name: "Infrastructure", slug: "infrastructure", position: 3, is_default: false, color: "#F59E0B", description: "Cloud, network, or platform-level failures." },
    { name: "Data", slug: "data", position: 4, is_default: false, color: "#3B82F6", description: "Data loss, corruption, pipeline failure, or integrity issues." },
    { name: "Third Party", slug: "third_party", position: 5, is_default: false, color: "#10B981", description: "Vendor or external dependency outage affecting your systems." }
  ].freeze

  # Forms are defined in IncidentForm::DEFAULTS and materialized on
  # demand via Workspace#ensure_incident_form!. No seeding required.

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

  # Kept as a no-op for backwards compatibility (older migrations call it).
  # Forms now come from `IncidentForm::DEFAULTS` and need no per-workspace
  # rows; see `Workspace#ensure_incident_form!` for lazy materialization.
  def setup_incident_forms!
    # no-op
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
