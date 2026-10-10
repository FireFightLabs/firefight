# Starts each scheduled check that is due (Investigation::Check). Taking a check moves its schedule on in the same
# statement, so two sweeps never start it twice, and a check still running from last time is not started again.
class HalonCheckSweepJob < ApplicationJob
  queue_as :background

  def perform(now = Time.current)
    Investigation::Check.due(now).includes(:workspace).find_each do |check|
      next unless check.claim_due!(now)
      next if Investigation.start_refusal(check.workspace)

      InvestigationService.new(check.workspace).start(check, trigger_source: Investigation::TRIGGER_SCHEDULE)
    end
  end
end
