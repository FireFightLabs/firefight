# One turn of a conversation: the agent reads the question, uses what it can reach, and replies.
class Conversation::Runner
  def initialize(conversation)
    @conversation = conversation
  end

  def run(question:)
    chat = chat_record
    chat.discard_interrupted_reply!
    delivery.thinking!

    outcome = responder.run(
      chat: chat,
      tools: Conversation::Tools.for(@conversation, offer: ->(tools) { chat.with_tools(*tools) }),
      question: question,
      context: context,
      budget: budget,
      on_step: method(:report_step)
    ) do |turn|
      @conversation.record_turn!(turns_used: turn.turns_used, spent_cents: turn.spent_cents)
    end

    delivery.answered!(reply_for(outcome, chat))
    outcome
  end

  private

  def delivery = @delivery ||= Conversation::Delivery.new(@conversation)

  def responder
    @responder ||= FirefightAi::Responder.new(
      @conversation.workspace, inferable: @conversation.subject, member: @conversation.started_by,
      output_style: WorkspaceAdapter.for(@conversation.workspace).ai_output_style
    )
  end

  # What the person reads. A turn that ran out of room says so rather than going quiet.
  def reply_for(outcome, chat)
    return NO_ROOM_LEFT unless outcome.status == FirefightAi::AgentLoop::STATUS_ANSWERED

    chat.messages.reload.last&.content.presence || NO_ROOM_LEFT
  end

  NO_ROOM_LEFT = "I could not finish that one. Ask me something narrower, or start an investigation.".freeze

  def report_step(step)
    titles[step.key] = step.tool.to_s.tr("_", " ").humanize if step.tool.present?
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

  def chat_record
    @conversation.chat || create_chat
  end

  def create_chat
    choice = responder.ai_model
    chat = @conversation.build_chat(workspace: @conversation.workspace)
    chat.provider = choice.provider if choice.provider.present?
    chat.assume_model_exists = choice.provider.present? && !FirefightAi.registered?(choice.model)
    chat.model = choice.model
    chat.save!
    chat
  end
end
