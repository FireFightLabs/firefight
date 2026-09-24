# Starts a run. The loop itself is InvestigationJob, which is also what speaks in the channel.
class InvestigationService
  def initialize(workspace)
    @workspace = workspace
  end

  # Nil means a live run already exists, so the caller says so rather than starting a second.
  # The run announces itself when it starts working, so nothing is posted here.
  # The brief is what whoever asked said about it (Investigation::Brief), which the run reads for clues.
  # A run with no subject answers where it was asked, a channel or the chat and tool call that asked.
  def start(subject, trigger_source:, triggered_by: nil, brief: {}, channel_id: nil, conversation: nil, tool_call_id: nil)
    investigation = claim(
      subject, trigger_source: trigger_source, triggered_by: triggered_by, brief: brief,
      answer_in: { channel_id: channel_id, conversation: conversation, tool_call_id: tool_call_id }
    )
    return nil unless investigation

    InvestigationJob.perform_later(investigation.id)
    investigation
  end

  private

  # The partial unique index is the guard, so a second request loses the insert.
  def claim(subject, trigger_source:, triggered_by:, brief:, answer_in:)
    limits = @workspace.investigation_limits
    @workspace.investigations.create!(
      subject: subject,
      trigger_source: trigger_source,
      triggered_by: triggered_by,
      brief: brief,
      max_turns: limits.max_turns,
      max_spend_cents: limits.max_spend_cents,
      **answer_in
    )
  rescue ActiveRecord::RecordNotUnique
    nil
  end
end
