module Events
  class PinAddedHandler
    def self.execute(workspace, payload)
      handle(workspace, payload, IncidentEvent::MESSAGE_PINNED)
    end

    def self.handle(workspace, payload, event_type)
      event = payload["event"] || {}
      return unless event.dig("item", "type") == "message"

      channel_id = event.dig("item", "channel")
      message_ts = event.dig("item", "message", "ts") || event.dig("item", "ts")
      return unless channel_id && message_ts

      incident = workspace.incidents.in_channel(channel_id).recent.first
      return unless incident

      member = workspace.workspace_memberships.find_by(platform_user_id: event["user"])
      permalink = Events::Permalinks.fetch(workspace, channel_id, message_ts)

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
    end
  end
end
