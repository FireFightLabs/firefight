class Conversation::LiveDelivery
  EVENT_THINKING = "thinking"
  EVENT_STEP = "step"
  EVENT_CHUNK = "chunk"
  EVENT_ANSWERED = "answered"
  EVENT_FAILED = "failed"
  EVENT_WAITING = "waiting"

  STATUS_RUNNING = "running"
  STATUS_DONE = "done"
  STATUS_WAITING = "waiting"
  STATUS_CANCELLED = "cancelled"
  STATUS_FAILED = "failed"
  STATUSES = {
    FirefightAi::AgentLoop::STEP_RUNNING => STATUS_RUNNING, FirefightAi::AgentLoop::STEP_DONE => STATUS_DONE
  }.freeze

  # No headers, since an answer is a chat reply and not a document.
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

  # Text written so far lands before the step.
  def step(key:, step:, status:, kind: Chat::Tools::KIND_ACT, seconds: 0, failed: false)
    @text.flush!
    shown = failed ? STATUS_FAILED : STATUSES.fetch(status)
    broadcast(
      type: EVENT_STEP, key: key, title: step.title, headline: step.headline, asked: step.asked,
      status: shown, kind: kind, seconds: seconds, card: (step.card&.to_h if shown == STATUS_DONE)
    )
  end

  def chunk(text)
    @text.add(text)
  end

  def answered!(_reply)
    @text.flush!
    broadcast(type: EVENT_ANSWERED)
  end

  # Without this the page would wait forever after a failed turn.
  def failed!
    broadcast(type: EVENT_FAILED)
  end

  # The page reads the questions from the chat, so the event only says to look.
  def confirm!(_tool_calls)
    @text.flush!
    broadcast(type: EVENT_WAITING)
  end

  private

  def broadcast(payload)
    ConversationChannel.broadcast_to(@conversation, payload)
  end
end
