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
    return chat.decide!(tool_call_id, approved: false) unless approved

    Conversation::Mitigations.choose!(chat, tool_call_id, expires) unless expires.nil?
    for_chat &&= !Chat::DataRepairs.asks_each?(chat, tool_call_id)
    return chat.decide!(tool_call_id, approved: true, for_chat: for_chat) unless Conversation::OwnerAsks.ask!(chat, tool_call_id, by: by)

    name, provenance = chat.tool_calls.where(tool_call_id: tool_call_id).pick(:name, :provenance)
    chat.allow_tool!(name) if for_chat && provenance.nil?
    true
  end
  private_class_method :decide_one

  def self.approve_allowed(chat, by)
    chat.reload.awaiting_decision_allowable.select { |tool_call| chat.allows_tool?(tool_call.name) && !Chat::DataRepairs.asks_each?(chat, tool_call.tool_call_id) }
      .count { |tool_call| Conversation::OwnerAsks.ask!(chat, tool_call.tool_call_id, by: by) || chat.decide!(tool_call.tool_call_id, approved: true) }
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
