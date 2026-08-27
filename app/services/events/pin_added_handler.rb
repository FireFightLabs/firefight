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
      permalink = MessagePermalinks.fetch(workspace, channel_id, message_ts)

      incident.incident_events.create!(
        event_type: event_type,
        actor: member,
        metadata: {
          user_id: event["user"],
          message_ts: message_ts,
          channel_id: channel_id,
          thread_ts: event.dig("item", "message", "thread_ts"),
          permalink: permalink,
          message_text: message_text(workspace, channel_id, message_ts)
        }
      )
    end

    # The text is what makes the timeline entry readable without opening
    # Slack. It is decoration on the pin, so failing to fetch it never fails
    # the event.
    def self.message_text(workspace, channel_id, message_ts)
      workspace.adapter.fetch_message(channel_id: channel_id, message_id: message_ts)[:text].presence
    rescue AdapterError
      nil
    end
  end
end
