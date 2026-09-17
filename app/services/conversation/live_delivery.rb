# A dashboard chat watches its own conversation. Each move goes out over the socket as it happens,
# and the saved chat is still what the page reads once the turn is done.
class Conversation::LiveDelivery
  EVENT_THINKING = "thinking"
  EVENT_STEP = "step"
  EVENT_CHUNK = "chunk"
  EVENT_ANSWERED = "answered"
  EVENT_FAILED = "failed"

  # What the page calls a step it is showing. The loop only ever reports these two.
  STATUS_RUNNING = "running"
  STATUS_DONE = "done"
  STATUSES = {
    FirefightAi::AgentLoop::STEP_RUNNING => STATUS_RUNNING, FirefightAi::AgentLoop::STEP_DONE => STATUS_DONE
  }.freeze

  # The page shows an answer as it was written, so there is no markup for the model to use.
  OUTPUT_STYLE = <<~STYLE.freeze
    Write plain sentences with no markup. No asterisks, no headers, no backticks.
    Short paragraphs, and a list as one item per line starting with a dash.
  STYLE

  def initialize(conversation)
    @conversation = conversation
    @text = Conversation::ChunkBuffer.new { |text| broadcast(type: EVENT_CHUNK, text: text) }
  end

  def output_style = OUTPUT_STYLE

  def thinking!
    broadcast(type: EVENT_THINKING)
  end

  # A tool interrupts the answer, so whatever has been written lands before the step does.
  def step(key:, title:, status:)
    @text.flush!
    broadcast(type: EVENT_STEP, key: key, title: title, status: STATUSES.fetch(status))
  end

  def chunk(text)
    @text.add(text)
  end

  def answered!(_reply)
    @text.flush!
    broadcast(type: EVENT_ANSWERED)
  end

  # A turn that died sends nothing else, so the page would wait forever.
  def failed!
    broadcast(type: EVENT_FAILED)
  end

  private

  def broadcast(payload)
    ConversationChannel.broadcast_to(@conversation, payload)
  end
end
