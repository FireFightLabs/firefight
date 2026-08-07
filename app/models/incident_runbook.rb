class IncidentRunbook < ApplicationRecord
  belongs_to :incident
  belongs_to :runbook
  belongs_to :workspace
  belongs_to :attached_by, class_name: "WorkspaceMembership", optional: true
end
