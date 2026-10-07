class Conversation::LiveDelivery
  EVENT_THINKING = "thinking"
  EVENT_STEP = "step"
  EVENT_CHUNK = "chunk"
  EVENT_ANSWERED = "answered"
  EVENT_FAILED = "failed"
  EVENT_WAITING = "waiting"
  # A run this chat started moved, so its card looks again.
  EVENT_INVESTIGATION = "investigation"
  # The chat made room in the model's window, shown as a quiet line where it happened.
  EVENT_MADE_ROOM = "made_room"

  STATUS_RUNNING = "running"
  STATUS_DONE = "done"
  STATUS_WAITING = "waiting"
  STATUS_CANCELLED = "cancelled"
  STATUS_FAILED = "failed"
  # The provider answered that what a read asked about is not there, an answer rather than a failure (Chat::StepOutcome).
  STATUS_NOT_FOUND = "not_found"
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

  # Text written so far lands before the step. outcome is what the call got back, once it has.
  def step(key:, step:, status:, kind: Chat::Tools::KIND_ACT, seconds: 0, outcome: nil)
    @text.flush!
    shown = self.class.status_of(status, outcome)
    broadcast(
      type: EVENT_STEP, key: key, title: step.title, headline: step.headline, asked: step.asked,
      status: shown, kind: kind, seconds: seconds, card: (step.card&.to_h if shown == STATUS_DONE), outcome: outcome&.to_h
    )
  end

  OUTCOME_STATUSES = { Chat::StepOutcome::KIND_FAILED => STATUS_FAILED, Chat::StepOutcome::KIND_NOT_FOUND => STATUS_NOT_FOUND }.freeze

  def self.status_of(status, outcome) = OUTCOME_STATUSES.fetch(outcome&.kind) { STATUSES.fetch(status) }

  # Text written so far lands before the line, so it sits where the room was made.
  def made_room(compaction)
    @text.flush!
    broadcast(type: EVENT_MADE_ROOM, key: compaction.step_key, title: Chat::Compaction::SHOWN_AS, at: compaction.created_at.utc.iso8601(3))
  end

  def chunk(text)
    @text.add(text)
  end

  def answered!(_reply)
    @text.flush!
    broadcast(type: EVENT_ANSWERED)
  end

  # Without this the page would wait forever after a failed turn. What to say is already saved in the chat it reloads.
  def failed!(_text = nil)
    broadcast(type: EVENT_FAILED)
  end

  # The page reads the questions from the chat, so the event only says to look.
  def confirm!(_tool_calls)
    @text.flush!
    broadcast(type: EVENT_WAITING)
  end

  private

  # Action Cable hands broadcasts to a pool of threads, so they can reach the page out of order. Each says when it was
  # sent, in microseconds and never twice the same, and the page places it by that.
  def broadcast(payload)
    ConversationChannel.broadcast_to(@conversation, payload.merge(seq: next_seq))
  end

  def next_seq
    @seq = [ Process.clock_gettime(Process::CLOCK_REALTIME, :microsecond), (@seq || 0) + 1 ].max
  end
end
