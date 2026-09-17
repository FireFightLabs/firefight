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
      @conversation.record_turn!(turns_used: turn.turns_used, spent_cents: turn.spent_cents)
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

  # What the person reads. A turn that ran out of room says so in the chat as well, so the answer
  # that never came is not a silence on the next visit either.
  def reply_for(outcome, chat)
    return chat.messages.reload.last&.content.presence || NO_ROOM_LEFT if answered?(outcome)

    @conversation.note!(NO_ROOM_LEFT)
    NO_ROOM_LEFT
  end

  def answered?(outcome) = outcome.status == FirefightAi::AgentLoop::STATUS_ANSWERED

  def report_step(step)
    titles[step.key] = Chat::Tools.step_title(step.tool) if step.tool.present?
    title = titles[step.key]
    delivery.step(key: step.key, title: title, status: step.status) if title
  end

  def titles = @titles ||= {}

  def context
    incident = @conversation.incident
    return nil unless incident

    "You are in the channel for #{incident.identifier} #{incident.name}, status #{incident.incident_status.name}."
  end

  def budget
    FirefightAi::AgentLoop::Budget.new(
      max_spend_cents: @conversation.max_spend_cents, max_turns: @conversation.max_turns,
      turns_used: @conversation.turns_used, spent_cents: @conversation.spent_cents
    )
  end
end
