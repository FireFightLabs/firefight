# A code change paused at its spending limit: told where it came from, and decided by the person it runs as. Continue
# gives it another budget of the same size and carries it on at the start of a turn in the chat, through the very tool a
# chat offers them, so grants, approval rules and the ledger apply. Stop deletes the saved branch and closes the box.
class CodeAgentPauseService
  GONE = "This paused change is gone.".freeze
  COULD_NOT_CONTINUE = "The change could not be continued, so nothing more was written.".freeze
  COULD_NOT_STOP = "The saved branch could not be deleted just now. Delete it on the code host if it is still there.".freeze

  # Said on the step and in the thread, or to whoever asked when the chat has no thread.
  def self.tell!(pause)
    Conversation::LiveDelivery.code_fix_moved(pause.conversation) if pause.conversation
    destination = PullRequestFollowing.destination_of(pause.session)
    adapter = WorkspaceAdapter.for(pause.workspace)
    posted = if destination.thread_id.present?
      adapter.post_code_pause(channel_id: destination.channel_id, thread_id: destination.thread_id, pause: pause)
    elsif (user_id = pause.session.principal.try(:platform_user_id)).present?
      adapter.post_code_pause(channel_id: user_id, thread_id: nil, pause: pause)
    end
    pause.update_columns(message_channel_id: posted[:channel_id], message_id: posted[:message_id], told_at: Time.current) if posted.is_a?(Hash) && posted[:message_id]
  rescue AdapterError => error
    Rails.logger.warn({ event: "code_pause.untold", pause_id: pause.id, error: error.class.name }.to_json)
  end

  # Continue, pressed by the person the change runs as. Answers why not, or nil.
  def self.continue!(pause, by:)
    blocked = pause.decide_blocked_reason(by)
    return blocked if blocked
    return pause.reload.decide_blocked_reason(by) || "This was already decided." unless pause.decide!(by, to: CodeAgentSession::Pause::STATUS_CONTINUING)

    conversation = pause.conversation || thread_conversation(pause, by)
    return COULD_NOT_CONTINUE unless conversation

    pause.update_columns(conversation_id: conversation.id)
    conversation.expect_reply!
    ConversationReplyJob.perform_later(conversation.id, by.id, nil, nil, nil, pause.id)
    moved!(pause)
    nil
  end

  # Stop, pressed by the person the change runs as: the saved branch is deleted and the box closed. Answers why not, or nil.
  def self.stop!(pause, by:)
    blocked = pause.decide_blocked_reason(by)
    return blocked if blocked
    return pause.reload.decide_blocked_reason(by) || "This was already decided." unless pause.decide!(by, to: CodeAgentSession::Pause::STATUS_STOPPED)

    row = pause.session.integration_environment
    pack = row && Integrations::NativePack.fetch!(row.integration)
    pack.discard_pause!(row, pause) if pack.respond_to?(:discard_pause!)
    moved!(pause)
    nil
  rescue Integrations::Error => error
    Rails.logger.warn({ event: "code_pause.stop_failed", pause_id: pause.id, error: error.message.truncate(200) }.to_json)
    moved!(pause)
    COULD_NOT_STOP
  end

  def self.decided_words(pause) = pause.continuing? ? "The change carries on." : "The change was stopped and its saved work deleted."

  # The step's card and the thread's message say who decided, on the dashboard at once.
  def self.moved!(pause)
    keep_on_step!(pause)
    Conversation::LiveDelivery.code_fix_moved(pause.conversation) if pause.conversation
    return if pause.message_id.blank?

    WorkspaceAdapter.for(pause.workspace).update_code_pause(channel_id: pause.message_channel_id, message_id: pause.message_id, pause: pause)
  rescue AdapterError => error
    Rails.logger.warn({ event: "code_pause.redraw_failed", pause_id: pause.id, error: error.class.name }.to_json)
  end

  # The step the change ran under keeps the pause as decided, so a reload shows it.
  def self.keep_on_step!(pause)
    session = pause.session
    chat = session.place.try(:chat) if session.place.is_a?(Conversation)
    return unless chat && session.tool_call_id

    kept = chat.step_progresses.find_by(tool_call_id: session.tool_call_id)
    work = kept&.work
    return unless work

    work.pause_moved!(pause.to_h)
    Chat::StepProgress.keep!(chat, session.tool_call_id, work)
  end

  # A run's change that was not started from a chat carries on in its thread's own chat.
  def self.thread_conversation(pause, by)
    destination = PullRequestFollowing.destination_of(pause.session)
    return if destination.thread_id.blank? || by.platform_user_id.blank? || !pause.session.place.is_a?(Investigation::RemediationStep)

    investigation = pause.session.place.plan.finding.investigation
    Conversation::Opener.call(workspace: pause.workspace, incident: investigation.incident, channel_id: destination.channel_id,
                              thread_id: destination.thread_id, platform_user_id: by.platform_user_id)
  end

  # The change carried on as the person who pressed Continue, through the tool a chat offers them. Answers what it said.
  def self.run_continue!(turn, pause)
    row = pause.session.integration_environment
    tool = row&.integration&.tools&.find { |each| each.writes_code? && each.enabled? && each.available? }
    return "Continue did not run, since the code host's tool that writes code changes is no longer switched on." unless tool

    arguments = pause.arguments.merge(CodeAgentSession::Pause::CONTINUE_ARG => pause.id)
    Chat::Tools::Connection.new(turn, tool).run(arguments, environment_entry: row.environment, tool_call_id: nil, shown_as: tool.model_facing_name)
  rescue StandardError => error
    Rails.logger.warn({ event: "code_pause.continue_failed", pause_id: pause.id, error: error.class.name }.to_json)
    COULD_NOT_CONTINUE
  end

  # What Halon reads once the change carried on, before it tells the person how it went.
  def self.continued_note(pause, said)
    "The person pressed Continue on the code change in #{pause.repository} that paused at its spending limit, so it carried on. It answered:\n" \
      "#{FirefightAi::Evidence.frame('fix_code', said.to_s)}\nTell them how it went in a few sentences."
  end
end
