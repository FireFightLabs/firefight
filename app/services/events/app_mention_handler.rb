module Events
  class AppMentionHandler
    def self.execute(workspace, payload)
      event = payload["event"] || {}

      channel_id = event["channel"]
      return unless channel_id

      incident = workspace.incidents.active.in_channel(channel_id).first
      return unless incident

      user_text = strip_mention(event["text"])
      return if user_text.blank?
      return unless defined?(FirefightAi)

      gate = Entitlements.check(workspace, Entitlements::AI)
      return notify_blocked(workspace, channel_id, event["user"], gate.message) if gate.blocked?

      unready = agent?(workspace) && Investigation.unknown_window_reason(workspace)
      return notify_blocked(workspace, channel_id, event["user"], unready) if unready

      acknowledge(workspace, channel_id, event["ts"])

      parent_thread_ts = event["thread_ts"]
      reply_thread_ts = parent_thread_ts || event["ts"]

      if agent?(workspace)
        return investigate(workspace, channel_id, event, user_text) if investigate?(user_text)

        return answer_as_agent(workspace, incident, channel_id, reply_thread_ts, event, user_text)
      end

      IncidentAiResponseJob.perform_later(
        incident.id,
        channel_id,
        reply_thread_ts,
        user_text,
        parent_thread_ts
      )
    end

    # The agent answers with tools and remembers the thread. Without the flag, the old reply stands.
    def self.agent?(workspace)
      FeatureFlags.enabled?(workspace, FeatureFlags::AI_SRE)
    end
    private_class_method :agent?

    # Only as the first word, so a question that mentions investigating is still a question.
    def self.investigate?(user_text) = user_text.split(/\s+/, 2).first.to_s.casecmp?(Identifiers::SUBCOMMAND_INVESTIGATE)
    private_class_method :investigate?

    # The same command /ff investigate runs, so the permission, the refusals and the brief are decided in one place.
    def self.investigate(workspace, channel_id, event, user_text)
      command = Command.new(
        platform: workspace.platform, workspace_id: workspace.id, user_id: event["user"], text: user_text,
        channel_id: channel_id, metadata: { command: Identifiers::COMMAND_FF }
      )
      refusal = CommandDispatcher.dispatch(command)
      notify_blocked(workspace, channel_id, event["user"], refusal[:text]) if refusal.is_a?(Hash)
    end
    private_class_method :investigate

    def self.answer_as_agent(workspace, incident, channel_id, thread_id, event, user_text)
      conversation = Conversation::Opener.call(
        workspace: workspace, incident: incident, channel_id: channel_id,
        thread_id: thread_id, platform_user_id: event["user"]
      )
      asker = Conversation::Opener.member(workspace, event["user"])
      Conversation::Asking.ask(conversation, user_text, asker: asker)
    end
    private_class_method :answer_as_agent

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
