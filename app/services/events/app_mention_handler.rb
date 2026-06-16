module Events
  class AppMentionHandler
    def self.execute(platform, payload)
      event = payload["event"] || {}

      workspace = Workspace.find_by(platform: platform, platform_id: payload["team_id"])
      return unless workspace

      channel_id = event["channel"]
      return unless channel_id

      incident = workspace.incidents.active.in_channel(channel_id).first
      return unless incident

      user_text = strip_mention(event["text"])
      return if user_text.blank?
      return unless defined?(FirefightAi)

      gate = Entitlements.check(workspace, Entitlements::AI)
      return notify_blocked(workspace, channel_id, event["user"], gate.message) if gate.blocked?

      acknowledge(workspace, channel_id, event["ts"])

      parent_thread_ts = event["thread_ts"]
      reply_thread_ts = parent_thread_ts || event["ts"]

      FirefightAi::IncidentResponseJob.perform_later(
        incident.id,
        channel_id,
        reply_thread_ts,
        user_text,
        parent_thread_ts
      )
    rescue StandardError => e
      Rails.logger.warn({ event: "events.app_mention.failed", error: e.message, team_id: payload["team_id"] }.to_json)
    end

    def self.strip_mention(text)
      text.to_s.gsub(/<@[^>]+>/, "").squish
    end
    private_class_method :strip_mention

    def self.acknowledge(workspace, channel_id, timestamp)
      workspace.adapter.add_reaction(channel_id: channel_id, message_id: timestamp, name: "eyes")
    rescue AdapterError => e
      Rails.logger.info({ event: "events.app_mention.reaction_failed", error: e.message }.to_json)
    end
    private_class_method :acknowledge

    def self.notify_blocked(workspace, channel_id, user_id, message)
      return if message.blank?

      workspace.adapter.post_ephemeral(channel_id: channel_id, user_id: user_id, text: message)
    rescue AdapterError => e
      Rails.logger.info({ event: "events.app_mention.blocked_notice_failed", error: e.message }.to_json)
    end
    private_class_method :notify_blocked
  end
end
