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
  # A call held for approval in this chat moved on, so its card looks again.
  EVENT_HELD_CALL = "held_call"
  # A change was refused for want of a pack, or the admins were asked for it, so its card looks again.
  EVENT_PACK_REFUSAL = "pack_refusal"
  # A watch this chat started began, said something or ended, so its card and lines look again.
  EVENT_WATCH = "watch"
  # A tool call asked the person for a secret or made one for them to reveal, or a value was set, so its card looks again.
  EVENT_SECRET_ENTRY = "secret_entry"
  # A pull request Halon opened from this chat needs attention, or Fix it was pressed, so its card looks again.
  EVENT_PULL_REQUEST = "pull_request"
  # A code change paused on a step, or someone decided on it, so the chat looks again.
  EVENT_CODE_FIX = "code_fix"
  # Something contradicted a memory, so the chat asks the person which is right.
  EVENT_MEMORY = "memory"
  # A plan Halon keeps in this chat was made, moved a step, or someone pressed something on it, so its card looks again.
  EVENT_PLAN = "plan"
  # A statement's rows were counted or copied, a temporary change started, was kept or undone, or an owner was asked or
  # answered, so those cards look again.
  EVENT_SAFEGUARD = "safeguard"
  # A helper this chat handed a check to started, took a step or reported, so the step drawing it looks again.
  EVENT_HELPERS = "helpers"

  STATUS_RUNNING = "running"
  STATUS_DONE = "done"
  STATUS_WAITING = "waiting"
  STATUS_CANCELLED = "cancelled"
  STATUS_FAILED = "failed"
  # The provider answered that what a read asked about is not there, an answer rather than a failure (Chat::StepOutcome).
  STATUS_NOT_FOUND = "not_found"
  # One of Firefight's own rules refused the call, which is final rather than a failure (Chat::StepOutcome).
  STATUS_REFUSED = "refused"
  STATUSES = {
    FirefightAi::AgentLoop::STEP_RUNNING => STATUS_RUNNING, FirefightAi::AgentLoop::STEP_DONE => STATUS_DONE
  }.freeze

  # No headers, since an answer is a chat reply and not a document.
  OUTPUT_STYLE = <<~STYLE.freeze
    Use markdown: **bold**, _italic_, bullet and numbered lists, `code`, and fenced code blocks.
    Do not use markdown headers (#). Use **bold text** instead. Keep paragraphs short.
  STYLE

  # Said from outside a turn, so it carries no place among the turn's events.
  def self.held_call_moved(conversation)
    ConversationChannel.broadcast_to(conversation, type: EVENT_HELD_CALL)
  end

  def self.watch_moved(conversation)
    ConversationChannel.broadcast_to(conversation, type: EVENT_WATCH)
  end

  def self.safeguard_moved(conversation)
    ConversationChannel.broadcast_to(conversation, type: EVENT_SAFEGUARD)
  end

  def self.pack_refused(conversation)
    ConversationChannel.broadcast_to(conversation, type: EVENT_PACK_REFUSAL)
  end

  def self.pull_request_moved(conversation)
    ConversationChannel.broadcast_to(conversation, type: EVENT_PULL_REQUEST)
  end

  def self.code_fix_moved(conversation)
    ConversationChannel.broadcast_to(conversation, type: EVENT_CODE_FIX)
  end

  def self.memory_asked(conversation)
    ConversationChannel.broadcast_to(conversation, type: EVENT_MEMORY)
  end

  def self.secret_entry_moved(conversation)
    ConversationChannel.broadcast_to(conversation, type: EVENT_SECRET_ENTRY)
  end

  def self.plan_moved(conversation)
    ConversationChannel.broadcast_to(conversation, type: EVENT_PLAN)
  end

  def initialize(conversation)
    @conversation = conversation
    @text = Conversation::ChunkBuffer.new { |text| broadcast(type: EVENT_CHUNK, text: text) }
  end

  def output_style = OUTPUT_STYLE

  def thinking!
    broadcast(type: EVENT_THINKING)
  end

  # Text written so far lands before the step. outcome is what the call got back, once it has. progress is what a coding
  # agent the step runs has done so far (Chat::CodeFixProgress).
  def step(key:, step:, status:, kind: Chat::Tools::KIND_ACT, seconds: 0, outcome: nil, progress: nil)
    @text.flush!
    shown = self.class.status_of(status, outcome)
    broadcast(
      type: EVENT_STEP, key: key, title: step.title, headline: step.headline, asked: step.asked,
      status: shown, kind: kind, seconds: seconds, card: (step.card&.to_h if shown == STATUS_DONE || step.card&.shown_while_running?), outcome: outcome&.to_h,
      progress: progress&.to_h
    )
  end

  # How often a page is told about a coding agent's work at most. The page counts the time itself.
  PROGRESS_EVERY = 1

  # The step again, still running, with what its coding agent has done so far.
  def progress(key:, step:, progress:, kind: Chat::Tools::KIND_ACT)
    return unless progress_pace.due?(key, progress)

    broadcast(
      type: EVENT_STEP, key: key, title: step.title, headline: step.headline, asked: step.asked,
      status: STATUS_RUNNING, kind: kind, seconds: 0, card: nil, outcome: nil, progress: progress.to_h
    )
  end

  # The page reads the helpers from the chat, so the event only says to look.
  def helpers(key:, helpers:)
    broadcast(type: EVENT_HELPERS, key: key) if helpers.any?
  end

  OUTCOME_STATUSES = {
    Chat::StepOutcome::KIND_FAILED => STATUS_FAILED, Chat::StepOutcome::KIND_NOT_FOUND => STATUS_NOT_FOUND,
    Chat::StepOutcome::KIND_REFUSED => STATUS_REFUSED
  }.freeze

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

  # The page reads its confirmations from the chat when the turn ends, so a withdrawn one is gone without a word.
  def withdrawn!(_tool_calls) = nil

  # Nothing of a lost turn's answer is kept here, so there is nothing to end.
  def cut_off! = nil

  private

  def progress_pace = @progress_pace ||= Chat::CodeFixProgress::Pace.new(every: PROGRESS_EVERY)

  # Action Cable hands broadcasts to a pool of threads, so they can reach the page out of order. Each says when it was
  # sent, in microseconds and never twice the same, and the page places it by that.
  def broadcast(payload)
    ConversationChannel.broadcast_to(@conversation, payload.merge(seq: next_seq))
  end

  def next_seq
    @seq = [ Process.clock_gettime(Process::CLOCK_REALTIME, :microsecond), (@seq || 0) + 1 ].max
  end
end
