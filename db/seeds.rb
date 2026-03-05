# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

[
  { key: "triage", name: "Triage", description: "Potential incident under investigation; not yet confirmed as active.", position: 1 },
  { key: "active", name: "Active", description: "Confirmed incident actively being worked by responders.", position: 2 },
  { key: "closed", name: "Closed", description: "Incident resolved and no longer actively managed.", position: 3 },
  { key: "canceled", name: "Canceled", description: "False positive, duplicate, or invalid incident; excluded from resolved metrics.", position: 4 }
].each do |attrs|
  IncidentLifecycleStage.find_or_create_by!(key: attrs[:key]) do |stage|
    stage.assign_attributes(attrs.except(:key))
  end
end
