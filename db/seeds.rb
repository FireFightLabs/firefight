# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

[
  { key: "triage", name: "Triage", description: "Potential incident under investigation, not yet confirmed as active.", position: 1 },
  { key: "active", name: "Active", description: "Confirmed incident actively being worked by responders.", position: 2 },
  { key: "closed", name: "Closed", description: "Incident resolved and no longer actively managed.", position: 3 },
  { key: "canceled", name: "Canceled", description: "False positive, duplicate, or invalid incident. Excluded from resolved metrics.", position: 4 }
].each do |attrs|
  IncidentLifecycleStage.find_or_create_by!(key: attrs[:key]) do |stage|
    stage.assign_attributes(attrs.except(:key))
  end
end

# System actions for the Ability Gateway (schema-loaded environments skip
# the data migration that seeds these)
Ability::Action.sync_system_actions!

# Backfill: ensure all workspaces have a "Canceled" status
canceled_stage = IncidentLifecycleStage.find_by(key: "canceled")
if canceled_stage
  Workspace.find_each do |workspace|
    workspace.incident_statuses.find_or_create_by!(slug: "canceled") do |status|
      status.name = "Canceled"
      status.incident_lifecycle_stage = canceled_stage
      status.position = workspace.incident_statuses.maximum(:position).to_i + 1
      status.is_default = false
      status.color = "#999999"
      status.description = "False positive, duplicate, or invalid incident"
    end
  end
end
