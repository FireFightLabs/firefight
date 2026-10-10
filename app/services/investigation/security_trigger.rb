# The security module's trigger: a security event a connected provider reported, such as a leaked secret, starts Halon
# on it once, in the channel of the team that owns where it happened, else the workspace's monitoring channel. The
# event is kept as an Investigation::Notice, so a second delivery of the same alert starts nothing, and only the same
# alert getting worse, such as a leaked secret found public, starts Halon again.
class Investigation::SecurityTrigger
  def initialize(workspace)
    @workspace = workspace
  end

  # The run it started, or nil when the workspace turned the trigger off, cannot run Halon, or already said this.
  def receive!(event)
    return nil unless @workspace.halon_security_events_enabled?
    return nil if Investigation.start_refusal(@workspace)

    resource = place_on_map(event.place)
    notice = Investigation::Notice.observe!(@workspace, reading(event, resource))
    # Two deliveries of one alert can arrive together, and only the one that takes the notice starts Halon.
    return nil unless notice&.claim!

    channel_id = Investigation::Notice.channel_for(@workspace, resource)
    started = InvestigationService.new(@workspace).start(
      nil, trigger_source: Investigation::TRIGGER_SECURITY_EVENT, channel_id: channel_id,
           brief: Investigation::Brief.from({ Investigation::Brief::KEY_SYMPTOM => symptom(event), Investigation::Brief::KEY_NAMES => [ event.place ] },
                                            source: Investigation::Brief::SOURCE_SECURITY_EVENT)
    )
    unless started
      notice.unsaid_because!(Investigation::Notice::NOT_STARTED)
      return nil
    end

    # The run is how it is said, on the run's page at least, so a second delivery of the same alert starts nothing.
    notice.update!(investigation: started)
    notice.said!(channel_id: channel_id, message_id: nil)
    notice.update_columns(unsaid_reason: Investigation::Notice::RUN_PAGE_ONLY) unless channel_id
    started
  end

  private

  def reading(event, resource)
    Investigation::Notice::Reading.new(
      signal: Investigation::Notice::SIGNAL_LEAKED_SECRET, topic: "#{event.what} in #{event.reference}",
      summary: "#{event.provider} found a leaked #{event.what} in #{event.place}#{', and it is public' if event.public}.",
      severity: event.public ? Investigation::Notice::SEVERITY_HIGH : Investigation::Notice::SEVERITY_MEDIUM, resource: resource,
      reference: "#{event.provider.parameterize}:#{event.reference}"
    )
  end

  # What Halon is asked to work out, in the words of the event. The secret itself is never in a provider's alert.
  def symptom(event)
    found = "#{event.provider} found a leaked #{event.what} in #{event.place} (#{event.reference})#{', and it is public' if event.public}."
    "#{found} Work out what it reaches and what was done with it, and how to revoke and replace it. #{event.url}".strip
  end

  def place_on_map(place)
    ResourceMap::Resource.where(workspace: @workspace, kind: ResourceMap::KIND_REPOSITORY).present.referenced(@workspace, place).first
  end
end
