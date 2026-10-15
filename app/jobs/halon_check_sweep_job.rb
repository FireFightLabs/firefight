# Starts each scheduled check that is due (Investigation::Check). Taking a check moves its schedule on in the same
# statement, so two sweeps never start it twice, and a check still running from last time is not started again.
# Each workspace, and whether it can run Halon, is read once a sweep, however many of its checks are due.
class HalonCheckSweepJob < ApplicationJob
  queue_as :background

  def perform(now = Time.current)
    workspaces = {}
    refusals = {}
    Investigation::Check.due(now).includes(:workspace).find_each do |check|
      workspace = workspaces[check.workspace_id] ||= check.workspace
      next unless check.claim_due!(now)

      check.workspace = workspace
      next if refusals.fetch(workspace.id) { refusals[workspace.id] = Investigation.start_refusal(workspace) }

      InvestigationService.new(workspace).start(check, trigger_source: Investigation::TRIGGER_SCHEDULE)
    end
  end
end
