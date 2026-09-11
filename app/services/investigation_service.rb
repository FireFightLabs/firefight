# Starts a run and tells the channel it is working. The loop itself is InvestigationJob.
class InvestigationService
  def initialize(workspace)
    @workspace = workspace
  end

  def start(incident, trigger_source:, triggered_by: nil)
    investigation = claim(incident, trigger_source: trigger_source, triggered_by: triggered_by)
    return nil unless investigation

    announce(incident)
    InvestigationJob.perform_later(investigation.id)
    investigation
  end

  def live_for(incident)
    incident.investigations.live.first
  end

  private

  # The partial unique index is the real guard, so a second request loses the insert
  # and the caller attaches to the run that is already going.
  def claim(incident, trigger_source:, triggered_by:)
    @workspace.investigations.create!(
      incident: incident,
      trigger_source: trigger_source,
      triggered_by: triggered_by,
      max_turns: @workspace.investigation_turn_limit,
      max_tokens: @workspace.investigation_token_limit,
      confidence_threshold: @workspace.investigation_confidence_bar
    )
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def announce(incident)
    return if incident.channel_id.blank?

    @workspace.adapter.post_message(
      channel_id: incident.channel_id,
      text: "Investigating #{incident.identifier}, I will post what I find.",
      blocks: nil
    )
  rescue AdapterError => e
    Rails.logger.warn({
      event: "investigation.announcement_undelivered", incident_id: incident.id, error: e.class.name
    }.to_json)
  end
end
