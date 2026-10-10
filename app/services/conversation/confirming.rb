# A person's answer to the calls the agent paused on, from the dashboard or a Slack button.
class Conversation::Confirming
  # The row lock orders two answers given at once, so exactly one of them, the one deciding the last question, resumes the turn.
  # Allowing a tool for the rest of the chat also approves the other open calls to it, since they are asked about the same
  # thing, except a call asked after something was read from outside, which is answered on its own.
  def self.decide(conversation, decisions, by:)
    chat = conversation.chat
    return false unless chat

    resume = conversation.with_lock do
      decided = decisions.count do |decision|
        chat.decide!(decision[:tool_call_id], approved: decision[:approved], for_chat: decision[:for_chat].present?)
      end
      decided += approve_allowed(chat)
      decided.positive? && chat.awaiting_decision.none?
    end
    if resume
      conversation.expect_reply!
      ConversationReplyJob.perform_later(conversation.id, by.id)
    end
    resume
  end

  def self.approve_allowed(chat)
    chat.reload.awaiting_decision_allowable.select { |tool_call| chat.allows_tool?(tool_call.name) }
      .count { |tool_call| chat.decide!(tool_call.tool_call_id, approved: true) }
  end
  private_class_method :approve_allowed

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
