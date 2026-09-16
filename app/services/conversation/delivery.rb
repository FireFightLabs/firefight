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

  def answered!(reply)
    adapter.post_agent_reply(
      channel_id: @conversation.channel_id, thread_id: @conversation.thread_id,
      answer_id: @answer_id, text: reply
    )
  end

  private

  def adapter = @adapter ||= WorkspaceAdapter.for(@conversation.workspace)
end
