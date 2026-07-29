class EventDispatcher
  def self.dispatch(platform, payload)
    event = payload["event"]
    return unless event

    # One check here covers every event handler: reactions, pins, mentions,
    # joins. Events carry no way to answer the user, so a suspended workspace's
    # events are dropped, and the command and dashboard paths carry the message.
    workspace = Workspace.find_by(platform: platform, platform_id: payload["team_id"])
    if workspace&.suspended?
      Rails.logger.info({ event: "event_dispatcher.suspended_workspace", workspace_id: workspace.id })
      return
    end

    case event["type"]
    when Identifiers::EVENT_REACTION_ADDED
      Events::ReactionAddedHandler.execute(platform, payload)
    when Identifiers::EVENT_MESSAGE
      Events::MessageHandler.execute(platform, payload)
    when Identifiers::EVENT_PIN_ADDED
      Events::PinAddedHandler.execute(platform, payload)
    when Identifiers::EVENT_PIN_REMOVED
      Events::PinRemovedHandler.execute(platform, payload)
    when Identifiers::EVENT_APP_MENTION
      Events::AppMentionHandler.execute(platform, payload)
    when Identifiers::EVENT_MEMBER_JOINED
      Events::MemberJoinedChannelHandler.execute(platform, payload)
    else
      Rails.logger.info({
        event: "event_dispatcher.unhandled_event",
        event_type: event["type"],
        team_id: payload["team_id"]
      }.to_json)
    end
  end
end
