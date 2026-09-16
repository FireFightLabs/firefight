# The app half of a run: the chat, the tools, and what each turn spent.
class Investigation::Runner
  # Another worker holds the run.
  class LeaseLost < StandardError; end

  Result = Data.define(:status, :error_summary)

  STOPPED_BY_A_RESPONDER = "Stopped by a responder".freeze

  def initialize(investigation)
    @investigation = investigation
  end

  def run
    delivery.start!
    chat = chat_record
    chat.discard_interrupted_reply!

    outcome = investigator.run(
      chat: chat,
      tools: Investigation::Tools.for(@investigation),
      seed_pack: @investigation.seed_pack,
      budget: budget,
      answered: -> { @investigation.reload.finding.present? },
      canceled: -> { @investigation.reload.cancel_requested? },
      on_step: method(:report_step)
    ) do |turn|
      unless @investigation.record_turn!(turns_used: turn.turns_used, spent_cents: turn.spent_cents)
        raise LeaseLost, "another worker holds this run"
      end
    end

    deliver(result_for(outcome))
  rescue FirefightAi::Canceled
    deliver(Result.new(status: Investigation::STATUS_CANCELED, error_summary: STOPPED_BY_A_RESPONDER))
  end

  private

  def delivery = @delivery ||= Investigation::Delivery.new(@investigation)

  def deliver(result)
    if @investigation.reload.finding
      delivery.answered!(@investigation.finding)
    else
      delivery.stopped!(result.error_summary)
    end
    result
  end

  # A reader sees the tools the agent reached for, not the ones it writes its findings with.
  def report_step(step)
    titles[step.key] = title_for(step.tool) if step.tool.present? && !internal?(step.tool)
    title = titles[step.key]
    delivery.step(key: step.key, title: title, status: step.status) if title
  end

  def titles = @titles ||= {}

  def internal?(tool_name)
    [ Investigation::Tools::Conclude.tool_name, Investigation::Tools::RecordHypothesis.tool_name ].include?(tool_name)
  end

  def title_for(tool_name)
    tool_name.to_s.tr("_", " ").humanize
  end

  def investigator
    @investigator ||= FirefightAi::Investigator.new(
      @investigation.workspace, inferable: @investigation, member: member
    )
  end

  # Inference rows name a person only when a person asked.
  def member
    @investigation.triggered_by if @investigation.triggered_by.is_a?(WorkspaceMembership)
  end

  def budget
    FirefightAi::AgentLoop::Budget.new(
      max_spend_cents: @investigation.max_spend_cents, max_turns: @investigation.max_turns,
      turns_used: @investigation.turns_used, spent_cents: @investigation.spent_cents
    )
  end

  def chat_record
    @investigation.chat || create_chat
  end

  # Records which model ran, without opening a connection to the provider.
  def create_chat
    choice = investigator.ai_model
    chat = @investigation.build_chat(workspace: @investigation.workspace)
    chat.provider = choice.provider if choice.provider.present?
    chat.assume_model_exists = choice.provider.present? && !FirefightAi.registered?(choice.model)
    chat.model = choice.model
    chat.save!
    chat
  end

  # An answer is the only success.
  def result_for(outcome)
    return Result.new(status: Investigation::STATUS_SUCCEEDED, error_summary: nil) if @investigation.reload.finding
    if outcome.status == FirefightAi::AgentLoop::STATUS_CANCELED
      return Result.new(status: Investigation::STATUS_CANCELED, error_summary: STOPPED_BY_A_RESPONDER)
    end

    Result.new(status: Investigation::STATUS_FAILED, error_summary: reason_for(outcome.status))
  end

  def reason_for(status)
    {
      FirefightAi::AgentLoop::STATUS_CANCELED => STOPPED_BY_A_RESPONDER,
      FirefightAi::AgentLoop::STATUS_OUT_OF_BUDGET => "Budget spent before it could answer",
      FirefightAi::AgentLoop::STATUS_OUT_OF_TURNS => "Stopped after too many turns",
      FirefightAi::AgentLoop::STATUS_STALLED => "Stopped talking without an answer",
      FirefightAi::AgentLoop::STATUS_REPEATED_TOOL_CALL => "Repeated the same tool call"
    }.fetch(status, "Ended without an answer")
  end
end
