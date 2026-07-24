class RunbookAttachmentService
  def initialize(workspace)
    @workspace = workspace
  end

  def auto_attach(incident)
    context = IncidentConditionEvaluator.context_for(incident)

    Runbook.matching(@workspace, context).each do |runbook|
      attach(incident: incident, runbook: runbook)
    end
  end

  def attach(incident:, runbook:, attached_by: nil)
    existing = incident.incident_runbooks.find_by(runbook: runbook)
    return existing if existing

    # Creation and update workflows can both evaluate the same incident
    # concurrently; the loser of the unique-index race takes the found row and
    # leaves the announcement to the winner.
    incident_runbook = incident.incident_runbooks.create_or_find_by!(runbook: runbook) do |record|
      record.workspace = @workspace
      record.attached_by = attached_by
    end
    return incident_runbook unless incident_runbook.previously_new_record?

    incident.incident_events.create!(
      event_type: IncidentEvent::RUNBOOK_ATTACHED,
      actor: attached_by,
      metadata: { runbook_id: runbook.id, runbook_slug: runbook.slug, runbook_name: runbook.name }
    )

    result = @workspace.adapter.post_runbook_message(
      channel_id: incident.channel_id,
      incident_runbook: incident_runbook
    )
    incident_runbook.update!(message_ts: result[:message_id])

    incident_runbook
  end

  def apply(incident_runbook:, applied_by:)
    return unless claim(incident_runbook, applied_by)

    incident = incident_runbook.incident
    runbook = incident_runbook.runbook
    action_service = IncidentActionService.new(@workspace)

    runbook.runbook_steps.each do |step|
      action_service.create_action(
        incident: incident,
        created_by: applied_by,
        action_type: IncidentAction::ACTION_TYPE_ACTION,
        description: step_description(step)
      )
    end

    incident.incident_events.create!(
      event_type: IncidentEvent::RUNBOOK_APPLIED,
      actor: applied_by,
      metadata: { runbook_id: runbook.id, runbook_slug: runbook.slug, runbook_name: runbook.name, action_count: runbook.runbook_steps.size }
    )

    return unless incident_runbook.message_ts

    @workspace.adapter.update_runbook_applied(
      channel_id: incident.channel_id,
      message_id: incident_runbook.message_ts,
      incident_runbook: incident_runbook
    )
  end

  private

  # Marks the attachment applied before any action is created, so a double
  # click or a redelivered interaction cannot fan out a second set of actions.
  def claim(incident_runbook, applied_by)
    claimed = IncidentRunbook.where(id: incident_runbook.id, applied_at: nil).update_all(
      applied_at: Time.current,
      applied_by_id: applied_by&.id,
      updated_at: Time.current
    ) == 1

    incident_runbook.reload if claimed
    claimed
  end

  def step_description(step)
    if step.instruction.present?
      "#{step.title}\n#{step.instruction}"
    else
      step.title
    end
  end
end
