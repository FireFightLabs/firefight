# A person's answer to the calls the agent paused on, from the dashboard or a Slack button.
class Conversation::Confirming
  # The row lock orders two answers given at once, so exactly one of them, the one deciding the last question, resumes the turn.
  # Allowing a tool for the rest of the chat also approves the other open calls to it, since they are asked about the same
  # thing, except a call asked after something was read from outside, which is answered on its own. A change customers
  # feel takes how long until it is undone (expires), and a call that stops something someone else started waits for
  # them to agree once confirmed (Conversation::OwnerAsks), so the turn resumes only once they answer.
  def self.decide(conversation, decisions, by:)
    chat = conversation.chat
    return false unless chat

    resume = conversation.with_lock do
      decided = decisions.count do |decision|
        decide_one(chat, decision[:tool_call_id], approved: decision[:approved], for_chat: decision[:for_chat].present?,
                                                  expires: decision[:expires], by: by)
      end
      decided += approve_allowed(chat, by)
      decided.positive? && chat.undecided.none?
    end
    if resume
      conversation.expect_reply!
      ConversationReplyJob.perform_later(conversation.id, by.id)
    end
    resume
  end

  def self.decide_one(chat, tool_call_id, approved:, for_chat:, expires:, by:)
    return chat.decide!(tool_call_id, approved: false, by: by) unless approved

    Conversation::Mitigations.choose!(chat, tool_call_id, expires) unless expires.nil?
    for_chat &&= !Chat::DataRepairs.asks_each?(chat, tool_call_id)
    return chat.decide!(tool_call_id, approved: true, for_chat: for_chat, by: by) unless Conversation::OwnerAsks.ask!(chat, tool_call_id, by: by)

    name, provenance = chat.tool_calls.where(tool_call_id: tool_call_id).pick(:name, :provenance)
    chat.allow_tool!(name) if for_chat && provenance.nil?
    true
  end
  private_class_method :decide_one

  def self.approve_allowed(chat, by)
    chat.reload.awaiting_decision_allowable.select { |tool_call| chat.allows_tool?(tool_call.name) && !Chat::DataRepairs.asks_each?(chat, tool_call.tool_call_id) }
      .count { |tool_call| Conversation::OwnerAsks.ask!(chat, tool_call.tool_call_id, by: by) || chat.decide!(tool_call.tool_call_id, approved: true, by: by) }
  end
  private_class_method :approve_allowed

  # Redraws the confirmation last posted in the chat's thread once a call it asked about was answered somewhere else, or
  # ran, so the message always says how the call stands. Only the latest message is kept, so a call asked in an earlier
  # one is redrawn only from its own button. A chat on the dashboard or in an issue has no such message.
  # progress is a code change's work as it stands this moment, which is shown over the copy kept at the chat's pace.
  def self.redraw_latest(conversation, tool_call_id, progress: nil)
    return if conversation.confirmation_message_id.blank? || conversation.channel_id.blank?
    return if conversation.personal? || conversation.mcp? || conversation.issue?

    chat = conversation.chat
    return unless chat

    latest = chat.tool_calls.where.not(approval: nil).reorder(created_at: :desc).pick(:message_id)
    return unless latest && latest == chat.tool_calls.where(tool_call_id: tool_call_id).pick(:message_id)

    redraw(conversation, tool_call_id, channel_id: conversation.channel_id, message_id: conversation.confirmation_message_id, progress: progress)
  end

  # A call the person approved moved on, a code change getting further or the call answering, so its message says how
  # it stands.
  def self.moved(conversation, tool_call_id, progress: nil)
    chat = conversation.chat
    return unless chat && chat.tool_calls.where(tool_call_id: tool_call_id).pick(:approval) == Chat::APPROVAL_APPROVED

    redraw_latest(conversation, tool_call_id, progress: progress)
  end

  ANSWERED_WORDS = { Chat::APPROVAL_APPROVED => "approved", Chat::APPROVAL_OWNER_ASKED => "approved", Chat::APPROVAL_DENIED => "cancelled" }.freeze
  NOT_ANSWERED = "These changes were already answered.".freeze

  # What the person is told once they answered on the dashboard, a sentence per change in how it now stands, such as
  # "Delete set_1 is approved." nil when none of them was answered.
  def self.answered_words(conversation, tool_call_ids)
    calls = conversation.chat.tool_calls.where(tool_call_id: tool_call_ids).order(:created_at)
    said = calls.filter_map do |call|
      words = ANSWERED_WORDS[call.approval]
      "#{Chat::Tools.confirmation(call).action.upcase_first} is #{words}." if words
    end
    said.join(" ").presence
  end

  # A call the person approved whose turn was lost never answers, so it ends as interrupted and its message says it
  # failed, rather than working forever. decided_before keeps a call approved since, whose turn may be running, out of it.
  def self.interrupted!(conversation, decided_before:)
    chat = conversation.chat
    return unless chat

    closed = chat.close_approved_calls!(decided_before: decided_before)
    redraw_latest(conversation, closed.first.tool_call_id) if closed.any?
  end

  # From the recovery sweep. A turn past the reply ceiling is no longer swept, so a call approved before then that still
  # never answered, in a chat whose turn nobody holds, is ended here.
  def self.recover!
    decided_before = Conversation::REPLY_CEILING.ago
    Chat.where(id: Chat::Message.where(id: Chat.stale_approved_calls(decided_before).select(:message_id)).select(:chat_id)).find_each do |chat|
      conversation = chat.owner
      next unless conversation.is_a?(Conversation) && !conversation.answer_owed?

      interrupted!(conversation, decided_before: decided_before)
    end
  end

  # Redraws the message the answered call was asked in, with every call asked alongside it.
  def self.redraw(conversation, tool_call_id, channel_id:, message_id:, progress: nil)
    return if message_id.blank?

    asked_together = conversation.chat.asked_with(tool_call_id).map do |tool_call|
      shown = Chat::Tools.confirmation(tool_call)
      progress && tool_call.tool_call_id == tool_call_id ? shown.with(progress: progress) : shown
    end
    WorkspaceAdapter.for(conversation.workspace).update_agent_confirmation(
      channel_id: channel_id, message_id: message_id, conversation_id: conversation.id, confirmations: asked_together
    )
  rescue AdapterError => error
    Rails.logger.warn({ event: "conversation.confirmation_redraw_failed", conversation_id: conversation.id, error: error.message }.to_json)
  end
end
