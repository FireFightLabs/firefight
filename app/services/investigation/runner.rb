# The app half of a run: the chat, the tools, and what each turn spent.
class Investigation::Runner
  # Another worker holds the run.
  class LeaseLost < StandardError; end

  Result = Data.define(:status, :error_summary)

  # Why the loop stopped, in the plain words the model keeps.
  STOP_REASONS = {
    FirefightAi::AgentLoop::STATUS_CANCELED => Investigation::STOPPED_BY_A_RESPONDER,
    FirefightAi::AgentLoop::STATUS_OUT_OF_BUDGET => Investigation::BUDGET_SPENT,
    FirefightAi::AgentLoop::STATUS_OUT_OF_TURNS => Investigation::TOO_MANY_TURNS,
    FirefightAi::AgentLoop::STATUS_STALLED => Investigation::STALLED,
    FirefightAi::AgentLoop::STATUS_REPEATED_TOOL_CALL => Investigation::REPEATED_CALL
  }.freeze

  def initialize(investigation)
    @investigation = investigation
  end

  def run
    delivery.start!
    chat = chat_record
    chat.discard_interrupted_reply!

    outcome = investigator.run(
      chat: chat,
      tools: Investigation::Tools.for(@investigation, offer: Chat::Tools.offer_to(chat)) + Chat::Tools.known(@investigation, chat),
      seed_pack: @investigation.seed_pack,
      budget: budget,
      answered: -> { @investigation.reload.finding.present? },
      canceled: -> { @investigation.reload.cancel_requested? },
      on_step: method(:report_step),
      nudge: chat.method(:nudge!),
      memory: chat
    ) do |turn|
      unless @investigation.record_turn!(turns_used: turn.turns_used, spent_micros: turn.spent_micros)
        raise LeaseLost, "another worker holds this run"
      end
    end

    deliver(result_for(outcome))
  rescue FirefightAi::Canceled
    deliver(Result.new(status: Investigation::STATUS_CANCELED, error_summary: Investigation::STOPPED_BY_A_RESPONDER))
  end

  private

  def delivery = @delivery ||= (@investigation.rehearsal? ? Investigation::QuietDelivery : Investigation::Delivery).new(@investigation)

  def deliver(result)
    if @investigation.reload.finding
      delivery.answered!(@investigation.finding)
    else
      delivery.stopped!(result.error_summary)
    end
    result
  end

  def report_step(step)
    titles[step.key] = Chat::Tools.step(step.tool, step.arguments)&.title if step.tool.present?
    title = titles[step.key]
    delivery.step(key: step.key, title: title, status: step.status) if title
  end

  def titles = @titles ||= {}

  def investigator
    @investigator ||= FirefightAi::Investigator.new(
      @investigation.workspace, inferable: @investigation, member: member, model: @investigation.model_choice
    )
  end

  # Inference rows name a person only when a person asked.
  def member
    @investigation.triggered_by if @investigation.triggered_by.is_a?(WorkspaceMembership)
  end

  def budget
    FirefightAi::AgentLoop::Budget.new(
      max_spend_cents: @investigation.max_spend_cents, max_turns: @investigation.max_turns,
      turns_used: @investigation.turns_used, spent_micros: @investigation.spent_micros
    )
  end

  def chat_record
    @investigation.chat || Chat.open!(
      owner: @investigation, workspace: @investigation.workspace, model_choice: investigator.ai_model
    )
  end

  # An answer is the only success.
  def result_for(outcome)
    return Result.new(status: Investigation::STATUS_SUCCEEDED, error_summary: nil) if @investigation.reload.finding
    if outcome.status == FirefightAi::AgentLoop::STATUS_CANCELED
      return Result.new(status: Investigation::STATUS_CANCELED, error_summary: Investigation::STOPPED_BY_A_RESPONDER)
    end

    Result.new(status: Investigation::STATUS_FAILED, error_summary: reason_for(outcome.status))
  end

  def reason_for(status) = STOP_REASONS.fetch(status, Investigation::ENDED_WITHOUT_AN_ANSWER)
end
