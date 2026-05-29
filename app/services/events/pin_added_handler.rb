module Events
  class PinAddedHandler
    def self.execute(platform, payload)
      handle(platform, payload, IncidentEvent::MESSAGE_PINNED)
    end

    def self.handle(platform, payload, event_type)
      event = payload["event"] || {}
      return unless event.dig("item", "type") == "message"

      workspace = Workspace.find_by(platform: platform, platform_id: payload["team_id"])
      return unless workspace

      channel_id = event.dig("item", "channel")
      message_ts = event.dig("item", "message", "ts") || event.dig("item", "ts")
      return unless channel_id && message_ts

      incident = workspace.incidents.in_channel(channel_id).recent.first
      return unless incident

      member = workspace.workspace_memberships.find_by(platform_user_id: event["user"])
      permalink = fetch_permalink(workspace, channel_id, message_ts)

      incident.incident_events.create!(
        event_type: event_type,
        actor: member,
        metadata: {
          user_id: event["user"],
          message_ts: message_ts,
          channel_id: channel_id,
          thread_ts: event.dig("item", "message", "thread_ts"),
          permalink: permalink
        }
      )
    rescue StandardError => e
      Rails.logger.warn({ event: "events.pin_added.failed", error: e.message, team_id: payload["team_id"] }.to_json)
    end

    def self.fetch_permalink(workspace, channel_id, message_ts)
      workspace.adapter.get_message_permalink(channel_id: channel_id, message_id: message_ts)[:permalink]
    rescue AdapterError
      nil
    end
    private_class_method :fetch_permalink
  end
end
