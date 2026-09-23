# A person's answer to the calls the agent paused on, from the dashboard or a Slack button.
class Conversation::Confirming
  # The row lock orders two answers given at once, so exactly one of them, the one deciding the last question, resumes the turn.
  def self.decide(conversation, decisions, by:)
    chat = conversation.chat
    return false unless chat

    resume = conversation.with_lock do
      decided = decisions.count { |decision| chat.decide!(decision[:tool_call_id], approved: decision[:approved]) }
      decided.positive? && chat.awaiting_decision.none?
    end
    if resume
      conversation.expect_reply!
      ConversationReplyJob.perform_later(conversation.id, by.id)
    end
    resume
  end

  # Redraws the message the answered call was asked in, with every call asked alongside it.
  def self.redraw(conversation, tool_call_id, channel_id:, message_id:)
    return if message_id.blank?

    asked_together = conversation.chat.asked_with(tool_call_id).map { |tool_call| Chat::Tools.confirmation(tool_call) }
    WorkspaceAdapter.for(conversation.workspace).update_agent_confirmation(
      channel_id: channel_id, message_id: message_id, conversation_id: conversation.id, confirmations: asked_together
    )
  rescue AdapterError => error
    Rails.logger.warn({ event: "conversation.confirmation_redraw_failed", conversation_id: conversation.id, error: error.message }.to_json)
  end
end
