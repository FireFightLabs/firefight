# Starts a run. The loop itself is InvestigationJob, which is also what speaks in the channel.
class InvestigationService
  def initialize(workspace)
    @workspace = workspace
  end

  # Nil means a live run already exists, so the caller says so rather than starting a second.
  # The run announces itself when it starts working, so nothing is posted here.
  def start(subject, trigger_source:, triggered_by: nil)
    investigation = claim(subject, trigger_source: trigger_source, triggered_by: triggered_by)
    return nil unless investigation

    InvestigationJob.perform_later(investigation.id)
    investigation
  end

  private

  # The partial unique index is the guard, so a second request loses the insert.
  def claim(subject, trigger_source:, triggered_by:)
    limits = @workspace.investigation_limits
    @workspace.investigations.create!(
      subject: subject,
      trigger_source: trigger_source,
      triggered_by: triggered_by,
      max_turns: limits.max_turns,
      max_spend_cents: limits.max_spend_cents
    )
  rescue ActiveRecord::RecordNotUnique
    nil
  end
end
