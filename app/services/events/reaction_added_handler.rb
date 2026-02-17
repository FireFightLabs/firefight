module Events
  class ReactionAddedHandler
    EMOJI_ACTION_TYPE_MAP = {
      "boom" => IncidentAction::ACTION_TYPE_ACTION,
      "arrow_forward" => IncidentAction::ACTION_TYPE_FOLLOWUP
    }.freeze

    def self.execute(platform, payload)
      event = payload["event"]
      reaction = event["reaction"]

      action_type = EMOJI_ACTION_TYPE_MAP[reaction]
      return unless action_type

      team_id = payload["team_id"]
      channel_id = event.dig("item", "channel")
      message_ts = event.dig("item", "ts")
      user_id = event["user"]

      workspace = Workspace.find_by(platform: platform, platform_id: team_id)
      return unless workspace

      incident = workspace.incidents.active.in_channel(channel_id).first
      return unless incident

      adapter = WorkspaceAdapter.for(workspace)

      message_text = fetch_message_text(adapter, channel_id, message_ts)
      source_message_link = fetch_permalink(adapter, channel_id, message_ts)

      adapter.post_action_from_reaction_prompt(
        channel_id: channel_id,
        user_id: user_id,
        action_type: action_type,
        message_text: message_text,
        incident_id: incident.id,
        source_message_link: source_message_link
      )
    rescue Slack::Client::ApiError => e
      Rails.logger.warn({
        event: "events.reaction_added.api_error",
        error: e.message,
        team_id: payload["team_id"],
        channel: event.dig("item", "channel")
      }.to_json)
    end

    def self.fetch_message_text(adapter, channel_id, ts)
      message = adapter.fetch_message(channel_id: channel_id, ts: ts)
      message&.dig(:text) || message&.dig("text") || ""
    rescue Slack::Client::ApiError
      ""
    end
    private_class_method :fetch_message_text

    def self.fetch_permalink(adapter, channel_id, message_ts)
      result = adapter.get_message_permalink(channel_id: channel_id, message_ts: message_ts)
      result[:permalink]
    rescue Slack::Client::ApiError
      nil
    end
    private_class_method :fetch_permalink
  end
end
