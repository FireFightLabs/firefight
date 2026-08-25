# Turns the incident's channel transcript into timeline notes, once, after the
# incident is over. Coordinates the engine call, the adapter lookups that give
# each note its link, and the event writes.
class MilestoneNotingService
  def initialize(workspace)
    @workspace = workspace
  end

  # Returns the events written, which is an empty list whenever the pass is
  # off, blocked, or has nothing new to read. A note is decoration on an
  # incident that already ended, so none of those are failures.
  def note!(incident)
    return [] unless FirefightAi.configuration.milestones_enabled?
    return [] unless Entitlements.allows?(@workspace, Entitlements::AI)

    messages = unread_messages(incident)
    return [] if messages.empty?

    write!(incident, extract(incident, messages), messages)
  end

  private

  def unread_messages(incident)
    scope = incident.incident_transcript_messages.kept.includes(workspace_membership: :user)
    scope = scope.where("message_id > ?", incident.milestones_noted_through) if incident.milestones_noted_through.present?
    scope.order(:posted_at).to_a
  end

  def extract(incident, messages)
    extractor.extract(
      incident,
      messages: messages,
      summary: FirefightAi::IncidentSummaryService.new(@workspace).fetch_or_refresh(incident),
      timeline: incident.incident_events.undismissed.chronological.includes(:actor).map(&:description)
    )
  end

  def extractor
    @extractor ||= FirefightAi::MilestoneExtractor.new(@workspace)
  end

  # The watermark moves whether or not the model found anything, so a pass
  # after a reopen reads only what was said since. Permalinks are fetched
  # before the transaction opens. They are adapter calls, and a slow one must
  # not hold a write open.
  def write!(incident, milestones, messages)
    sources = messages.index_by(&:message_id)
    noted = noted_message_ids(incident)
    watermark = messages.map(&:message_id).max

    rows = milestones.filter_map do |milestone|
      source = sources[milestone.message_id]
      next if source.nil? || !noted.add?(milestone.message_id)

      event_attributes(milestone, source, incident)
    end

    incident.transaction do
      events = rows.map { |attributes| incident.incident_events.create!(attributes) }
      incident.update!(milestones_noted_through: watermark)
      events
    end
  end

  def noted_message_ids(incident)
    incident.incident_events
      .where(event_type: IncidentEvent::MILESTONE_NOTED)
      .filter_map { |event| event.metadata.to_h["message_id"] }
      .to_set
  end

  # The note carries the person and the quote it was read from, so no surface
  # has to resolve an id or call Slack to render the row. created_at is the
  # source message's time, which is what puts the note where the conversation
  # was rather than where the inference ran.
  def event_attributes(milestone, source, incident)
    member = source.workspace_membership

    {
      event_type: IncidentEvent::MILESTONE_NOTED,
      created_at: source.posted_at,
      metadata: {
        kind: milestone.kind,
        statement: milestone.statement,
        confidence: milestone.confidence,
        member_id: member&.id,
        member_name: member&.display_name,
        member_avatar_url: member&.user&.avatar_url,
        message_id: source.message_id,
        message_text: source.content,
        permalink: permalink(incident, source.message_id),
        said_at: source.posted_at.utc.iso8601,
        inference_id: extractor.last_inference&.id
      }.compact
    }
  end

  def permalink(incident, message_id)
    return nil if incident.channel_id.blank?

    MessagePermalinks.fetch(@workspace, incident.channel_id, message_id)
  end
end
