# Starts each workflow whose Schedule or Once at time came, every minute. Taking a workflow moves its next time on in
# the same statement, so two sweeps never start it twice, and one start key per time it was due means a retried job
# never starts a second run. A start the workflow's limits refuse is kept on the workflow with why, for its page.
class WorkflowTriggerSweepJob < ApplicationJob
  queue_as :background

  def perform(now = Time.current)
    Workflow.due(now).includes(:live_version, :workspace).find_each do |workflow|
      next unless FeatureFlags.enabled?(workflow.workspace, FeatureFlags::WORKFLOWS)

      due_at = workflow.claim_due!(now)
      next unless due_at

      start(workflow, due_at)
    end
  end

  private

  def start(workflow, due_at)
    WorkflowRunService.new(workflow).start!(
      started_by_kind: Workflow::Run::STARTED_BY_TRIGGER, trigger_kind: workflow.live_version.trigger[Workflow::Trigger::KEY_KIND],
      trigger_payload: { "due_at" => due_at.iso8601 }, start_key: "trigger:#{due_at.utc.iso8601}"
    )
    workflow.trigger_started!
  rescue Workflow::Run::Refused => refused
    workflow.trigger_refused!(refused.message)
  end
end
