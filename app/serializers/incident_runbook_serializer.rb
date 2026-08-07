class IncidentRunbookSerializer < BaseSerializer
  object_as :incident_runbook

  type :string
  def id
    incident_runbook.id
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
  def claimed_count
    incident_runbook.incident.incident_actions.active
      .where(runbook_step_id: incident_runbook.runbook.runbook_steps.select(:id))
      .count
  end

  type :number
  def done_count
    incident_runbook.incident.incident_actions.active
      .where(runbook_step_id: incident_runbook.runbook.runbook_steps.select(:id), status: IncidentAction::STATUS_DONE)
      .count
  end
end
