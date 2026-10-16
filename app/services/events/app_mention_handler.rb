module Events
  class AppMentionHandler
    def self.execute(workspace, payload)
      event = payload["event"] || {}

      channel_id = event["channel"]
      return unless channel_id

      incident = workspace.incidents.active.in_channel(channel_id).first
      user_text = workspace.adapter.text_for_app(payload: payload)
      # Files alone are a question, since Halon reads them.
      return if user_text.blank? && event["files"].blank?
      return unless defined?(FirefightAi)
      # Outside an incident's channel Halon only takes an investigation, which answers in that channel.
      return unless incident || investigate?(user_text)

      gate = Entitlements.check(workspace, Entitlements::AI)
      return notify_blocked(workspace, channel_id, event, gate.message) if gate.blocked?

      unready = Investigation.unknown_window_reason(workspace)
      return notify_blocked(workspace, channel_id, event, unready) if unready

      acknowledge(workspace, channel_id, event["ts"])
      return investigate(workspace, channel_id, event, user_text) if investigate?(user_text)

      # In a live run's thread a mention is added to the run, which reads it at its next step.
      parent_thread_ts = event["thread_ts"]
      run = parent_thread_ts && Investigation.live_in_thread(workspace, parent_thread_ts)
      return add_note(workspace, run, channel_id, event, user_text) if run

      answer(workspace, incident, channel_id, parent_thread_ts || event["ts"], event, user_text)
    end

    # Only as the first word, so a question that mentions investigating is still a question.
    def self.investigate?(user_text) = user_text.split(/\s+/, 2).first.to_s.casecmp?(Identifiers::SUBCOMMAND_INVESTIGATE)
    private_class_method :investigate?

    # The same command /ff investigate runs, so the permission, the refusals and the brief are decided in one place.
    # Files shared with the mention go with the command, for the run to read as a chat does.
    def self.investigate(workspace, channel_id, event, user_text)
      files = shared_files(workspace, event, Conversation::Opener.member(workspace, event["user"]))
      command = Command.new(
        platform: workspace.platform, workspace_id: workspace.id, user_id: event["user"], text: user_text,
        channel_id: channel_id, metadata: { command: Identifiers::COMMAND_FF, Command::SHARED_FILE_IDS => files.map(&:id) }
      )
      refusal = CommandDispatcher.dispatch(command)
      return notify_blocked(workspace, channel_id, event, refusal[:text], marked: true) if refusal.is_a?(Hash)

      # The run answers in its own live checklist, so the mention is done once the run has started.
      workspace.adapter.mark_done(channel_id: channel_id, message_id: event["ts"])
    end
    private_class_method :investigate

    def self.add_note(workspace, run, channel_id, event, user_text)
      member = Conversation::Opener.member(workspace, event["user"])
      files = shared_files(workspace, event, member)
      refusal = run.add_note_from(read_by_model(workspace, user_text), member: member, source: AbilityGateway::SOURCE_SLACK, files: files, as_written: user_text)
      return notify_blocked(workspace, channel_id, event, refusal, marked: true) if refusal

      # The run shows it read the note among its steps, so the mention is done once the note is taken.
      workspace.adapter.mark_done(channel_id: channel_id, message_id: event["ts"])
    end
    private_class_method :add_note

    def self.answer(workspace, incident, channel_id, thread_id, event, user_text)
      asker = Conversation::Opener.member(workspace, event["user"])
      Conversation.ask_from_thread!(asker: asker, workspace: workspace, incident: incident, source: AbilityGateway::SOURCE_SLACK) do
        conversation = Conversation::Opener.call(
          workspace: workspace, incident: incident, channel_id: channel_id,
          thread_id: thread_id, platform_user_id: event["user"]
        )
        Conversation::Asking.ask(conversation, read_by_model(workspace, user_text), asker: asker, files: shared_files(workspace, event, asker),
                                 as_written: user_text, acknowledged_message_id: event["ts"])
      end
    rescue AbilityGateway::Denied => e
      notify_blocked(workspace, channel_id, event, AuthorizedDispatch.denied_message(e), marked: true)
    end
    private_class_method :answer

    # Taken the same way whatever the mention does, with the same limits and refusals.
    def self.shared_files(workspace, event, sender)
      Conversation::SharedFiles.receive(workspace: workspace, files: event["files"], sender: sender)
    end
    private_class_method :shared_files

    # People and channels named with their ids kept, so Halon reads who was meant and can act on them.
    def self.read_by_model(workspace, text)
      workspace.adapter.message_for_model(text: text)
    end
    private_class_method :read_by_model

    def self.acknowledge(workspace, channel_id, timestamp)
      workspace.adapter.mark_working(channel_id: channel_id, message_id: timestamp)
    end
    private_class_method :acknowledge

    # Said to the person alone, in the thread they asked in and in their direct messages, where it stays once they
    # reload. The message stops showing that Halon is working on it.
    def self.notify_blocked(workspace, channel_id, event, message, marked: false)
      return if message.blank?

      workspace.adapter.unmark_working(channel_id: channel_id, message_id: event["ts"]) if marked
      workspace.adapter.post_refusal(channel_id: channel_id, thread_id: event["thread_ts"], user_id: event["user"], text: message)
    rescue AdapterError => e
      Rails.logger.info({ event: "events.app_mention.blocked_notice_failed", error: e.message }.to_json)
    end
    private_class_method :notify_blocked
  end
end
