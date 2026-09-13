# Starts a run and tells the channel it is working. The loop itself is InvestigationJob.
class InvestigationService
  def initialize(workspace)
    @workspace = workspace
  end

  # Nil means a live run already exists, so the caller says so rather than starting a second.
  def start(incident, trigger_source:, triggered_by: nil)
    investigation = claim(incident, trigger_source: trigger_source, triggered_by: triggered_by)
    return nil unless investigation

    announce(incident)
    InvestigationJob.perform_later(investigation.id)
    investigation
  end

  private

  # The partial unique index is the guard, so a second request loses the insert.
  def claim(incident, trigger_source:, triggered_by:)
    limits = @workspace.investigation_limits
    @workspace.investigations.create!(
      incident: incident,
      trigger_source: trigger_source,
      triggered_by: triggered_by,
      max_turns: limits.max_turns,
      max_spend_cents: limits.max_spend_cents
    )
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def announce(incident)
    return if incident.channel_id.blank?

    @workspace.adapter.post_message(
      channel_id: incident.channel_id,
      text: "Investigating #{incident.identifier}. I will post what I find.",
      blocks: nil
    )
  rescue AdapterError => e
    Rails.logger.warn({
      event: "investigation.announcement_undelivered", incident_id: incident.id, error: e.message
    })
  end
end
