module Events
  class PinAddedHandler
    def self.execute(workspace, payload)
      handle(workspace, payload, IncidentEvent::MESSAGE_PINNED)
    end

    def self.handle(workspace, payload, event_type)
      pinned = workspace.adapter.pinned_message(payload: payload)
      return unless pinned

      channel_id = pinned[:channel_id]
      message_ts = pinned[:message_id]
      return unless channel_id && message_ts

      incident = workspace.incidents.in_channel(channel_id).recent.first
      return unless incident
      return if incident.own_pinned_message?(message_ts)

      member = workspace.workspace_memberships.find_by(platform_user_id: pinned[:user_id])
      permalink = MessagePermalinks.fetch(workspace, channel_id, message_ts)

      incident.incident_events.create!(
        event_type: event_type,
        actor: member,
        metadata: {
          user_id: pinned[:user_id],
          message_ts: message_ts,
          channel_id: channel_id,
          thread_ts: pinned[:thread_id],
          permalink: permalink,
          message_text: message_text(workspace, channel_id, message_ts)
        }
      )
    end

    # The text is decoration on the pin, so failing to fetch it never fails the event.
    def self.message_text(workspace, channel_id, message_ts)
      workspace.adapter.fetch_message(channel_id: channel_id, message_id: message_ts)&.dig(:text).presence
    rescue AdapterError
      nil
    end
  end
end
