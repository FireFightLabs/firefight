# One turn of a conversation: the agent reads the question, uses what it can reach, and replies.
class Conversation::Runner
  NO_ROOM_LEFT = "I could not finish that one. Ask me something narrower, or start an investigation.".freeze

  def initialize(conversation, asker:)
    @conversation = conversation
    @turn = Conversation::Turn.new(conversation, asker: asker)
  end

  def run
    @marked = Time.current
    chat = @conversation.chat_record
    chat.discard_interrupted_reply!
    delivery.thinking!

    outcome = responder.run(
      chat: chat,
      tools: Conversation::Tools.for(@turn, offer: Chat::Tools.offer_to(chat)) + Chat::Tools.known(@turn, chat),
      context: context,
      budget: budget,
      on_step: method(:report_step),
      on_chunk: ->(text) { delivery.chunk(text) },
      nudge: chat.method(:nudge!),
      memory: chat,
      check: -> { FirefightAi::Responder::CHECK if @looked_outside },
      hold: chat.method(:hold_last_reply!)
    ) do |turn|
      record(turn)
    end

    return ask_to_confirm(chat, outcome) if waiting?(outcome)

    @reply = reply_for(outcome, chat)
    # Cleared before the page is told, so its reload sees the turn as over.
    @conversation.reply_delivered!
    delivery.answered!(@reply)
    outcome
  end

  # What the person was told, for a caller that waits for the answer rather than watching it arrive.
  attr_reader :reply

  private

  def delivery = @delivery ||= Conversation::Delivery.for(@conversation)

  def responder
    @responder ||= FirefightAi::Responder.new(
      @conversation.workspace, inferable: @conversation.subject, member: @turn.asker,
      output_style: delivery.output_style
    )
  end

  # Saved too, so an unanswered turn is not silence on the next visit.
  def reply_for(outcome, chat)
    return chat.messages.reload.last&.content.presence || NO_ROOM_LEFT if answered?(outcome)

    @conversation.note!(NO_ROOM_LEFT)
    NO_ROOM_LEFT
  end

  def answered?(outcome) = outcome.status == FirefightAi::AgentLoop::STATUS_ANSWERED

  def waiting?(outcome) = outcome.status == FirefightAi::AgentLoop::STATUS_WAITING

  # The turn stops on calls that need the person's decision, and they are asked rather than answered.
  def ask_to_confirm(chat, outcome)
    chat.request_decisions!(chat.to_llm.pending_approvals.map(&:id))
    @conversation.reply_delivered!
    delivery.confirm!(chat.awaiting_decision.to_a)
    outcome
  end

  # The finished report only has the key, so the step is remembered from when it started.
  # A connected system is what an answer's claims about a cause rest on, so reading one is what owes the answer a check.
  def report_step(step)
    if step.tool.present?
      seen[step.key] = Chat::Tools.step(step.tool, step.arguments)
      kinds[step.key] = Chat::Tools.kind(step.tool, @conversation.workspace)
      @looked_outside ||= @conversation.workspace.reading_tool_names.include?(step.tool.to_s)
    end
    shown = seen[step.key]
    return unless shown

    done = step.status == FirefightAi::AgentLoop::STEP_DONE
    delivery.step(
      key: step.key, step: shown, status: step.status, kind: kinds[step.key],
      seconds: done ? seconds_since_last_step : 0, failed: done && failed?(step.key)
    )
  end

  # The wrapper marked the call as the tool answered, before the loop reports the step done.
  def failed?(key) = @conversation.chat.failed_tool_call_ids.include?(key)

  # Counted from the end of the last step, so the model's own time between calls counts as thinking.
  def seconds_since_last_step
    now = Time.current
    since = now - (@marked || now)
    @marked = now
    since.round
  end

  def seen = @seen ||= {}

  def kinds = @kinds ||= {}

  # Who the agent acts for, so it can answer what they may do and say who else can.
  def context
    [ asker_line, incident_line ].compact.join("\n")
  end

  def asker_line
    asker = @turn.asker
    return "You are acting for nobody known, so every tool will refuse." unless asker

    "You are acting for #{asker.display_name}, whose role in this workspace is #{asker.role}. Owners and admins can change settings and permissions, members respond to incidents."
  end

  def incident_line
    incident = @conversation.incident
    return nil unless incident

    "You are in the channel for #{incident.identifier} #{incident.name}, status #{incident.incident_status.name}."
  end

  # The loop counts from the start of this question, so the conversation is given what each turn added.
  def record(turn)
    @conversation.add_turn!(
      turns: turn.turns_used - counted.turns_used, spent_micros: turn.spent_micros - counted.spent_micros
    )
    @counted = turn
  end

  def counted = @counted ||= FirefightAi::AgentLoop::Turn.new(turns_used: 0, spent_micros: 0)

  # A question gets its own budget, so a long chat does not run dry for good. What every question
  # spent still adds up on the conversation.
  def budget
    FirefightAi::AgentLoop::Budget.new(
      max_spend_cents: @conversation.max_spend_cents, max_turns: @conversation.max_turns
    )
  end
end
