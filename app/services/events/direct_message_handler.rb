# A person writing to Halon in their direct messages with the app. Conversation::DirectMessages decides which chat it
# joins, and every refusal is said in the thread the person wrote in, since nobody else reads it.
module Events
  class DirectMessageHandler
    # Files alone are a question, since Halon reads them. Edits, deletions and everything else a platform says are not.
    TAKEN_SUBTYPES = [ nil, Identifiers::MESSAGE_SUBTYPE_FILE_SHARE ].freeze
    NOT_A_MEMBER = "I only answer people in this workspace, so I can't help you here.".freeze

    def self.execute(workspace, payload)
      event = payload["event"] || {}
      return unless TAKEN_SUBTYPES.include?(event["subtype"])
      # Halon's own messages and every other app's come back as events too.
      return if event["bot_id"].present? || event["app_id"].present? || event["user"].blank?
      return if event["text"].to_s.strip.empty? && event["files"].blank?
      return unless defined?(FirefightAi)

      channel_id = event["channel"]
      thread_id = event["thread_ts"] || event["ts"]
      return tell(workspace, channel_id, thread_id, NOT_A_MEMBER) if from_another_organisation?(payload, event)

      refusal = WorkspaceMemberProvisioner.refusal(workspace: workspace, platform_user_id: event["user"], adapter: workspace.adapter)
      return tell(workspace, channel_id, thread_id, refusal) if refusal

      sender = Conversation::Opener.member(workspace, event["user"])
      return tell(workspace, channel_id, thread_id, AuthorizedDispatch::UNRESOLVED_MESSAGE) unless sender

      gate = Entitlements.check(workspace, Entitlements::AI)
      return tell(workspace, channel_id, thread_id, gate.message) if gate.blocked?

      unready = Investigation.unknown_window_reason(workspace)
      return tell(workspace, channel_id, thread_id, unready) if unready

      # Marked before the question is queued, so an answer that comes back quickly always finds the mark to replace.
      acknowledge(workspace, channel_id, event["ts"])
      refusal = Conversation::DirectMessages.receive!(
        workspace: workspace, sender: sender, channel_id: channel_id, message_id: event["ts"], thread_id: thread_id,
        text: event["text"].to_s.strip, files: event["files"], source: AbilityGateway::SOURCE_SLACK
      )
      return unless refusal

      workspace.adapter.unmark_working(channel_id: channel_id, message_id: event["ts"])
      tell(workspace, channel_id, thread_id, refusal)
    end

    # Someone from another organisation reached through a shared connection. People in an organisation wide install
    # come from each of its workspaces, so the team is only compared for a single workspace.
    def self.from_another_organisation?(payload, event)
      team = event["user_team"].presence
      team.present? && payload["enterprise_id"].blank? && team != payload["team_id"]
    end
    private_class_method :from_another_organisation?

    def self.acknowledge(workspace, channel_id, timestamp)
      workspace.adapter.mark_working(channel_id: channel_id, message_id: timestamp)
    end
    private_class_method :acknowledge

    def self.tell(workspace, channel_id, thread_id, text)
      return if text.blank?

      workspace.adapter.post_threaded_message(channel_id: channel_id, parent_message_id: thread_id, text: text)
    rescue AdapterError => e
      Rails.logger.info({ event: "events.direct_message.notice_failed", error: e.message }.to_json)
    end
    private_class_method :tell
  end
end
