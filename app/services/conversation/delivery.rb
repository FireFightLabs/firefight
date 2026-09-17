# What the agent says while it is answering someone. The platform decides how it looks.
class Conversation::Delivery
  FAILED = "I could not finish that one. Ask me again, or narrow it down.".freeze

  # A platform counts every append against a rate limit, so the text goes up in second-long pieces
  # rather than token by token.
  STREAM_INTERVAL = 1.second
  STREAM_MAX_CHARS = 256

  def self.for(conversation)
    conversation.personal? ? Conversation::LiveDelivery.new(conversation) : new(conversation)
  end

  def initialize(conversation)
    @conversation = conversation
    @sent_text = false
    @lost_text = false
    @text = Conversation::ChunkBuffer.new(interval: STREAM_INTERVAL, max_chars: STREAM_MAX_CHARS) do |text|
      append(text)
    end
  end

  def thinking!
    @answer_id = adapter.start_agent_answer(
      channel_id: @conversation.channel_id, thread_id: @conversation.thread_id,
      user_id: @conversation.started_by.try(:platform_user_id)
    )[:answer_id]
  end

  # A step card sits between pieces of text, so what has been written lands first.
  def step(key:, title:, status:)
    @text.flush!
    adapter.report_agent_step(
      channel_id: @conversation.channel_id, answer_id: @answer_id, key: key, title: title, status: status
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

  # A turn that died leaves the person watching a spinner, so they are told instead.
  def failed!
    answered!(FAILED)
  end

  private

  # Text the person has already read is not repeated at the end. A piece Slack refused means they
  # have read only part of it, so the whole answer is posted after all.
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
