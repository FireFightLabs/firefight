# Runs one investigation: hands the engine the saved chat, the tools and the budget, and writes
# down what the run spent as it goes.
class Investigation::Runner
  # Another worker took the run over, so this one stops rather than writing over its work.
  class LeaseLost < StandardError; end

  Result = Data.define(:status, :error_summary)

  def initialize(investigation)
    @investigation = investigation
  end

  def run
    chat = chat_record
    chat.discard_interrupted_reply!

    outcome = investigator.run(
      chat: chat,
      tools: Investigation::Tools.for(@investigation),
      seed_pack: @investigation.seed_pack,
      budget: budget,
      answered: -> { @investigation.reload.finding.present? }
    ) do |turn|
      unless @investigation.record_turn!(turns_used: turn.turns_used, spent_cents: turn.spent_cents)
        raise LeaseLost, "another worker holds this run"
      end
    end

    result_for(outcome)
  end

  private

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

  # An answer is the only success. Everything else says why it stopped, and keeps the theories.
  def result_for(outcome)
    return Result.new(status: Investigation::STATUS_SUCCEEDED, error_summary: nil) if @investigation.reload.finding

    Result.new(status: Investigation::STATUS_FAILED, error_summary: reason_for(outcome.status))
  end

  def reason_for(status)
    {
      FirefightAi::AgentLoop::STATUS_OUT_OF_BUDGET => "Budget spent before it could answer",
      FirefightAi::AgentLoop::STATUS_OUT_OF_TURNS => "Stopped after too many turns",
      FirefightAi::AgentLoop::STATUS_STALLED => "Stopped talking without an answer",
      FirefightAi::AgentLoop::STATUS_REPEATED_TOOL_CALL => "Repeated the same tool call"
    }.fetch(status, "Ended without an answer")
  end
end
