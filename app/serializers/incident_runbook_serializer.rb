class IncidentRunbookSerializer < BaseSerializer
  object_as :incident_runbook

  type :string
  def id
    incident_runbook.id
  end

  # The attachment's id above identifies this incident's copy. This is the
  # runbook itself, which is what the settings screen opens.
  type :string
  def runbook_id
    incident_runbook.runbook_id
  end

  type :string
  def name
    incident_runbook.runbook.name
  end

  type :string
  def slug
    incident_runbook.runbook.slug
  end

  type :string, optional: true
  def summary
    incident_runbook.runbook.summary
  end

  type :string, optional: true
  def external_url
    incident_runbook.runbook.external_url
  end

  type :number
  def steps_count
    incident_runbook.runbook.runbook_steps.size
  end

  type :number
  def done_count
    incident_runbook.actions_by_step.count { |_step_id, action| action.done? }
  end
end
