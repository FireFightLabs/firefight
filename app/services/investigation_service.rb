# Starts a run. The loop itself is InvestigationJob, which is also what speaks in the channel.
class InvestigationService
  def initialize(workspace)
    @workspace = workspace
  end

  # Nil means a live run already exists, so the caller says so rather than starting a second.
  # The run announces itself when it starts working, so nothing is posted here.
  # The brief is what whoever asked said about it (Investigation::Brief), which the run reads for clues.
  # A run with no subject answers where it was asked, a channel or the chat and tool call that asked.
  # files are what was shared with the ask, unsent, which the run reads before its first step.
  # max_spend_cents caps the run below the workspace's own budget, as an alert storm's ceiling does.
  def start(subject, trigger_source:, triggered_by: nil, brief: {}, channel_id: nil, conversation: nil, tool_call_id: nil, files: [],
            max_spend_cents: nil)
    investigation = claim(
      subject, trigger_source: trigger_source, triggered_by: triggered_by, brief: brief, max_spend_cents: max_spend_cents,
      answer_in: { channel_id: channel_id, conversation: conversation, tool_call_id: tool_call_id }
    )
    return nil unless investigation

    investigation.hand_over_files!(files, by: (triggered_by if triggered_by.is_a?(WorkspaceMembership)))
    InvestigationJob.perform_later(investigation.id)
    investigation
  end

  private

  # The partial unique index is the guard, so a second request loses the insert. A savepoint keeps a lost insert from
  # spoiling a transaction the caller holds open, as an alert's start does around the storm budget.
  def claim(subject, trigger_source:, triggered_by:, brief:, answer_in:, max_spend_cents:)
    limits = @workspace.investigation_limits
    Investigation.transaction(requires_new: true) do
      @workspace.investigations.create!(
        subject: subject,
        trigger_source: trigger_source,
        triggered_by: triggered_by,
        brief: brief,
        max_turns: limits.max_turns,
        max_spend_cents: [ limits.max_spend_cents, max_spend_cents ].compact.min,
        **answer_in
      )
    end
  rescue ActiveRecord::RecordNotUnique
    nil
  end
end
