class EventDispatcher
  HANDLERS = {
    Identifiers::EVENT_REACTION_ADDED => Events::ReactionAddedHandler,
    Identifiers::EVENT_MESSAGE => Events::MessageHandler,
    Identifiers::EVENT_PIN_ADDED => Events::PinAddedHandler,
    Identifiers::EVENT_PIN_REMOVED => Events::PinRemovedHandler,
    Identifiers::EVENT_APP_MENTION => Events::AppMentionHandler,
    Identifiers::EVENT_MEMBER_JOINED => Events::MemberJoinedChannelHandler
  }.freeze

  # Events carry no way to answer the user, so unknown and suspended workspaces are dropped.
  # An AdapterError ends the event since the client already retried. Anything else propagates so ProcessEventJob retries, handler writes are idempotent.
  def self.dispatch(platform, payload)
    event = payload["event"]
    return unless event

    handler = HANDLERS[event["type"]]
    unless handler
      Rails.logger.info({
        event: "event_dispatcher.unhandled_event",
        event_type: event["type"],
        team_id: payload["team_id"]
      }.to_json)
      return
    end

    workspace = Workspace.find_by(platform: platform, platform_id: payload["team_id"])
    return unless workspace
    if workspace.suspended?
      Rails.logger.info({ event: "event_dispatcher.suspended_workspace", workspace_id: workspace.id })
      return
    end

    handler.execute(workspace, payload)
  rescue AdapterError => e
    Rails.logger.warn({
      event: "event_dispatcher.adapter_error",
      event_type: event["type"],
      team_id: payload["team_id"],
      error: e.message
    }.to_json)
  end
end
