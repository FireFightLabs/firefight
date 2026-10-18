# Starts each scheduled check that is due (Investigation::Check). Taking a check moves its schedule on in the same
# statement, so two sweeps never start it twice, and a check still running from last time is not started again.
# Each workspace, and whether it can run Halon, is read once a sweep, however many of its checks are due.
class HalonCheckSweepJob < ApplicationJob
  queue_as :background

  def perform(now = Time.current)
    workspaces = {}
    refusals = {}
    Investigation::Check.due(now).includes(:workspace, :owner).find_each do |check|
      workspace = workspaces[check.workspace_id] ||= check.workspace
      next pause(check, now) if check.owner_gone?
      next unless check.claim_due!(now)

      check.workspace = workspace
      next if refusals.fetch(workspace.id) { refusals[workspace.id] = Investigation.start_refusal(workspace) }

      InvestigationService.new(workspace).start(check, trigger_source: Investigation::TRIGGER_SCHEDULE)
    end
    Investigation::Check.untold_pauses.pluck(:id).each { |id| CheckOwnerGoneJob.perform_later(id) }
  end

  private

  # A check runs in its owner's name, so one whose owner left waits for a new one rather than running as nobody.
  def pause(check, now)
    CheckOwnerGoneJob.perform_later(check.id) if check.pause_for_gone_owner!(now)
  end
end
