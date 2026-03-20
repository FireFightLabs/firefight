class EventDispatcher
  def self.dispatch(platform, payload)
    event = payload["event"]
    return unless event

    case event["type"]
    when "reaction_added"
      Events::ReactionAddedHandler.execute(platform, payload)
    when "message"
      Events::MessageHandler.execute(platform, payload)
    when "pin_added"
      Events::PinAddedHandler.execute(platform, payload)
    when "pin_removed"
      Events::PinRemovedHandler.execute(platform, payload)
    when "app_mention"
      Events::AppMentionHandler.execute(platform, payload)
    when "member_joined_channel"
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
