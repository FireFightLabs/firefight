class EventDispatcher
  def self.dispatch(platform, payload)
    event = payload["event"]
    return unless event

    case event["type"]
    when "reaction_added"
      Events::ReactionAddedHandler.execute(platform, payload)
    else
      Rails.logger.info({
        event: "event_dispatcher.unhandled_event",
        event_type: event["type"],
        team_id: payload["team_id"]
      }.to_json)
    end
  end
end
