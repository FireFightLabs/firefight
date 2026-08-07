class IncidentRunbook < ApplicationRecord
  belongs_to :incident
  belongs_to :runbook
  belongs_to :workspace
  belongs_to :attached_by, class_name: "WorkspaceMembership", optional: true

  # Every surface rendering this attachment asks the same question: which
  # action, if any, belongs to each step.
  def actions_by_step
    @actions_by_step ||= incident.runbook_step_actions.slice(*runbook.runbook_steps.map(&:id))
  end
end
