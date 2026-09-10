IncidentLifecycleStage.seed!

# Schema-loaded environments skip the data migration that seeds these.
Ability::Action.sync_system_actions!

# Defined by the constant workspace creation uses so the two never drift.
canceled_defaults = Workspace::IncidentDefaults::DEFAULT_STATUSES.find { |status| status[:stage] == IncidentLifecycleStage::CANCELED }
canceled_stage = IncidentLifecycleStage.find_by(key: IncidentLifecycleStage::CANCELED)
if canceled_stage && canceled_defaults
  Workspace.find_each do |workspace|
    workspace.incident_statuses.find_or_create_by!(slug: canceled_defaults[:slug]) do |status|
      status.assign_attributes(canceled_defaults.except(:slug, :stage, :position))
      status.incident_lifecycle_stage = canceled_stage
      status.position = workspace.incident_statuses.maximum(:position).to_i + 1
    end
  end
end
