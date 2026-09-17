# What the agent says while it is answering someone. The platform decides how it looks.
class Conversation::Delivery
  def initialize(conversation)
    @conversation = conversation
  end

  def thinking!
    @answer_id = adapter.start_agent_answer(
      channel_id: @conversation.channel_id, thread_id: @conversation.thread_id,
      user_id: @conversation.started_by.try(:platform_user_id)
    )[:answer_id]
  end

  def step(key:, title:, status:)
    adapter.report_agent_step(
      channel_id: @conversation.channel_id, answer_id: @answer_id, key: key, title: title, status: status
    )
  end

  # The answer is already saved in the chat, and the turn has been paid for, so a platform failure
  # is logged rather than retried into a second model call.
  def answered!(reply)
    adapter.post_agent_reply(
      channel_id: @conversation.channel_id, thread_id: @conversation.thread_id,
      answer_id: @answer_id, text: reply
    )
  rescue AdapterError => error
    Rails.logger.warn({
      event: "conversation.reply_undelivered", conversation_id: @conversation.id, error: error.message
    }.to_json)
  end

  private

  def adapter = @adapter ||= WorkspaceAdapter.for(@conversation.workspace)
end
