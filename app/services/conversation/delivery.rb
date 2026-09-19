# What the agent says while it is answering someone. The platform decides how it looks.
class Conversation::Delivery
  FAILED = "Something went wrong on my side, so I did not finish that one. Ask me again.".freeze

  def self.for(conversation)
    conversation.personal? ? Conversation::LiveDelivery.new(conversation) : new(conversation)
  end

  def initialize(conversation)
    @conversation = conversation
    @sent_text = false
    @lost_text = false
    cadence = adapter.agent_stream_cadence
    @text = Conversation::ChunkBuffer.new(interval: cadence[:interval], max_chars: cadence[:max_chars]) do |text|
      append(text)
    end
  end

  def output_style = adapter.ai_stream_output_style

  def thinking!
    @answer_id = adapter.start_agent_answer(
      channel_id: @conversation.channel_id, thread_id: @conversation.thread_id,
      user_id: @conversation.started_by.try(:platform_user_id)
    )[:answer_id]
  end

  # Text written so far lands before the step card, which shows the tool by name and not its query.
  def step(key:, step:, status:)
    @text.flush!
    adapter.report_agent_step(
      channel_id: @conversation.channel_id, answer_id: @answer_id, key: key, title: step.title, status: status
    )
  end

  def chunk(text)
    @text.add(text)
  end

  # The answer is already saved in the chat, and the turn has been paid for, so a platform failure
  # is logged rather than retried into a second model call.
  def answered!(reply)
    @text.flush!
    adapter.post_agent_reply(
      channel_id: @conversation.channel_id, thread_id: @conversation.thread_id,
      answer_id: @answer_id, text: reply, streamed: streamed?
    )
  rescue AdapterError => error
    Rails.logger.warn({
      event: "conversation.reply_undelivered", conversation_id: @conversation.id, error: error.message
    }.to_json)
  end

  # Tells the person, or they would watch a spinner forever.
  def failed!
    answered!(FAILED)
  end

  def confirm!(tool_calls)
    @text.flush!
    adapter.ask_agent_confirmation(
      channel_id: @conversation.channel_id, thread_id: @conversation.thread_id, answer_id: @answer_id,
      conversation_id: @conversation.id, confirmations: tool_calls.map { |tool_call| Chat::Tools.confirmation(tool_call) }
    )
  rescue AdapterError => error
    Rails.logger.warn({ event: "conversation.confirmation_undelivered", conversation_id: @conversation.id, error: error.message }.to_json)
  end

  private

  # Streamed text is not repeated, unless a refused piece means the person missed part of it.
  def streamed? = @sent_text && !@lost_text

  def append(text)
    if adapter.append_agent_text(channel_id: @conversation.channel_id, answer_id: @answer_id, text: text)[:streaming]
      @sent_text = true
    else
      @lost_text = true
    end
  end

  def adapter = @adapter ||= WorkspaceAdapter.for(@conversation.workspace)
end
