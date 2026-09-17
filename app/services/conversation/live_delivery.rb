# A dashboard chat watches its own conversation. Each move goes out over the socket as it happens,
# and the saved chat is still what the page reads once the turn is done.
class Conversation::LiveDelivery
  EVENT_THINKING = "thinking"
  EVENT_STEP = "step"
  EVENT_CHUNK = "chunk"
  EVENT_ANSWERED = "answered"
  EVENT_FAILED = "failed"

  def initialize(conversation)
    @conversation = conversation
    @text = Conversation::ChunkBuffer.new { |text| broadcast(type: EVENT_CHUNK, text: text) }
  end

  def thinking!
    broadcast(type: EVENT_THINKING)
  end

  # A tool interrupts the answer, so whatever has been written lands before the step does.
  def step(key:, title:, status:)
    @text.flush!
    broadcast(type: EVENT_STEP, key: key, title: title, status: status.to_s)
  end

  def chunk(text)
    @text.add(text)
  end

  def answered!(_reply)
    @text.flush!
    broadcast(type: EVENT_ANSWERED)
  end

  # A turn that died sends nothing else, so the page would wait for an answer that is not coming.
  def failed!
    broadcast(type: EVENT_FAILED)
  end

  private

  def broadcast(payload)
    ConversationChannel.broadcast_to(@conversation, payload)
  end
end
