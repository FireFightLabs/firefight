class RunbookAttachmentService
  def initialize(workspace)
    @workspace = workspace
  end

  def auto_attach(incident)
    context = {
      incident_type: incident.incident_type_id,
      severity: incident.incident_severity_id
    }.compact

    Runbook.matching(@workspace, context).each do |runbook|
      attach(incident: incident, runbook: runbook)
    end
  end

  def attach(incident:, runbook:, attached_by: nil)
    existing = incident.incident_runbooks.find_by(runbook: runbook)
    return existing if existing

    incident_runbook = incident.incident_runbooks.create!(
      runbook: runbook,
      workspace: @workspace,
      attached_by: attached_by
    )

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
    return if incident_runbook.applied?

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

    incident_runbook.update!(applied_at: Time.current, applied_by: applied_by)

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

  def step_description(step)
    if step.instruction.present?
      "#{step.title}\n#{step.instruction}"
    else
      step.title
    end
  end
end
