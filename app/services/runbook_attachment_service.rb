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

  def attach_by_slug(incident:, slug:, attached_by: nil)
    runbook = @workspace.runbooks.active.find_by(slug: slug.to_s)
    if runbook.nil?
      available = @workspace.runbooks.active.ordered.pluck(:slug)
      raise ActiveRecord::RecordNotFound, "unknown runbook #{slug.to_s.inspect}. Valid: #{available.join(', ')}"
    end

    attach(incident: incident, runbook: runbook, attached_by: attached_by)
  end

  def attach(incident:, runbook:, attached_by: nil)
    existing = incident.incident_runbooks.find_by(runbook: runbook)
    return existing if existing

    # Creation and update workflows can both evaluate the same incident
    # concurrently. The loser of the unique-index race takes the found row and
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

  def refresh_message(incident_runbook)
    return unless incident_runbook&.message_ts

    @workspace.adapter.update_runbook_message(
      channel_id: incident_runbook.incident.channel_id,
      message_id: incident_runbook.message_ts,
      incident_runbook: incident_runbook
    )
  end

  def refresh_message_for_step(incident, runbook_step)
    return unless runbook_step

    refresh_message(incident.incident_runbooks.find_by(runbook_id: runbook_step.runbook_id))
  end
end
