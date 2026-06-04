class EventDispatcher
  def self.dispatch(platform, payload)
    event = payload["event"]
    return unless event

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
