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

  # The page renders markdown as it streams. Headers are left out, since an answer is a reply in a
  # chat and not a document.
  OUTPUT_STYLE = <<~STYLE.freeze
    Use markdown: **bold**, _italic_, bullet and numbered lists, `code`, and fenced code blocks.
    Do not use markdown headers (#). Use **bold text** instead. Keep paragraphs short.
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
  def step(key:, step:, status:)
    @text.flush!
    broadcast(
      type: EVENT_STEP, key: key, title: step.title, headline: step.headline, asked: step.asked,
      status: STATUSES.fetch(status)
    )
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
