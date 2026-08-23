# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

IncidentLifecycleStage.seed!

# System actions for the Ability Gateway (schema-loaded environments skip
# the data migration that seeds these)
Ability::Action.sync_system_actions!

# Backfill: ensure all workspaces have a "Canceled" status, defined by the
# same constant workspace creation uses so the two can never drift.
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
