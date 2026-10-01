# Runs a fix's steps away from the click, since a tool call can take longer than a request should. One at a time per
# fix, so a step marked done and an approval landing together never run the same step twice.
class InvestigationFixJob < ApplicationJob
  queue_as :default
  limits_concurrency key: ->(plan_id, *) { plan_id }, duration: 1.hour

  def perform(plan_id, step_id = nil, approval_id = nil)
    plan = Investigation::RemediationPlan.find_by(id: plan_id)
    return unless plan

    Investigation::FixRunner.new(plan).advance!(step_id: step_id, approval_id: approval_id)
  end
end
