# One turn of a conversation: the agent reads the question, uses what it can reach, and replies.
class Conversation::Runner
  NO_ROOM_LEFT = "I could not finish that one. Ask me something narrower, or start an investigation.".freeze

  def initialize(conversation)
    @conversation = conversation
  end

  def run
    chat = @conversation.chat_record
    chat.discard_interrupted_reply!
    delivery.thinking!

    outcome = responder.run(
      chat: chat,
      tools: Conversation::Tools.for(@conversation, offer: ->(tools) { chat.with_tools(*tools) }),
      context: context,
      budget: budget,
      on_step: method(:report_step),
      on_chunk: ->(text) { delivery.chunk(text) }
    ) do |turn|
      @conversation.record_turn!(turns_used: turn.turns_used, spent_micros: turn.spent_micros)
    end

    delivery.answered!(reply_for(outcome, chat))
    outcome
  end

  private

  def delivery = @delivery ||= Conversation::Delivery.for(@conversation)

  def responder
    @responder ||= FirefightAi::Responder.new(
      @conversation.workspace, inferable: @conversation.subject, member: @conversation.started_by,
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

  # The finished report only has the key, so the step is remembered from when it started.
  def report_step(step)
    seen[step.key] = Chat::Tools.step(step.tool, step.arguments) if step.tool.present?
    shown = seen[step.key]
    return unless shown

    delivery.step(key: step.key, step: shown, status: step.status)
  end

  def seen = @seen ||= {}

  def context
    incident = @conversation.incident
    return nil unless incident

    "You are in the channel for #{incident.identifier} #{incident.name}, status #{incident.incident_status.name}."
  end

  def budget
    FirefightAi::AgentLoop::Budget.new(
      max_spend_cents: @conversation.max_spend_cents, max_turns: @conversation.max_turns,
      turns_used: @conversation.turns_used, spent_micros: @conversation.spent_micros
    )
  end
end
