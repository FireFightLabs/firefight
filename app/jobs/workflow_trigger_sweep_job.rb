# Starts each workflow whose Schedule or Once at time came, every minute. Taking a workflow moves its next time on in
# the same statement, so two sweeps never start it twice, and one start key per time it was due means a retried job
# never starts a second run. A start past the workflow's most runs an hour is counted as skipped on it, any other start
# its limits refuse is kept on the workflow with why, for its page, and so is one that broke, which never stops the sweep reaching the workflows after it. Its time is given back so the next
# sweep tries it again, for RETRY_FOR. After that the time is given up: it is kept as a run that failed to start, which
# is said like any failed run, and the workflow's next time runs as usual.
class WorkflowTriggerSweepJob < ApplicationJob
  queue_as :background

  BROKE = "It could not start because of an error in Firefight.".freeze
  RETRY_FOR = 15.minutes
  GAVE_UP = "It could not start because of an error in Firefight, so after trying for 15 minutes this time was given up. " \
            "The next one runs as usual.".freeze

  def perform(now = Time.current)
    Workflow.due(now).includes(:live_version, :workspace).find_each do |workflow|
      due_at = workflow.claim_due!(now)
      next unless due_at

      start(workflow, due_at, now)
    end
    Workflow.given_up_unrecorded.includes(:live_version, :workspace).find_each do |workflow|
      give_up(workflow, workflow.given_up_at, now)
    end
  end

  private

  def start(workflow, due_at, now)
    WorkflowRunService.new(workflow).start!(
      started_by_kind: Workflow::Run::STARTED_BY_TRIGGER, trigger_kind: trigger_kind(workflow),
      trigger_payload: payload(due_at), start_key: start_key(due_at)
    )
    workflow.trigger_started!
  rescue Workflow::Run::Refused => refused
    workflow.trigger_start_refused!(refused)
  rescue StandardError => error
    Rails.logger.error({ event: "workflow_trigger.start_failed", workflow_id: workflow.id, due_at: due_at.iso8601, error: error.class.name, message: error.message }.to_json)
    return give_up(workflow, due_at, now) if now - due_at >= RETRY_FOR

    workflow.release_due!(due_at)
    workflow.trigger_refused!(BROKE)
  end

  # The time is kept as a run that failed to start, so the runs list shows it and the owning team, or whoever
  # published it, is told as for any failed run. Its start key is the time's, so a run made before it broke is the one
  # marked. Giving up that breaks is kept on the workflow and done again by the next sweep, which tells of it unless it
  # was told already. The time stays given up either way, so it never runs late.
  def give_up(workflow, due_at, now)
    run, = Workflow::Run.open!(workflow: workflow, start_key: start_key(due_at), version: workflow.live_version, status: Workflow::Run::STATUS_QUEUED,
                               trigger_kind: trigger_kind(workflow), trigger_payload: payload(due_at), agent: workflow.agent,
                               started_by_kind: Workflow::Run::STARTED_BY_TRIGGER)
    moved = run.move!(to: Workflow::Run::STATUS_FAILED, from: Workflow::Run::STATUS_QUEUED, error: GAVE_UP, finished_at: now)
    WorkflowRunEndedJob.perform_later(run.id) if moved || untold_give_up?(run)
    workflow.trigger_refused!(GAVE_UP)
    workflow.given_up_recorded!(due_at)
  rescue StandardError => error
    Rails.logger.error({ event: "workflow_trigger.give_up_failed", workflow_id: workflow.id, due_at: due_at.iso8601, error: error.class.name, message: error.message }.to_json)
    keep_given_up(workflow, due_at)
  end

  def keep_given_up(workflow, due_at)
    workflow.keep_given_up!(due_at)
  rescue StandardError => error
    Rails.logger.error({ event: "workflow_trigger.give_up_unkept", workflow_id: workflow.id, due_at: due_at.iso8601, error: error.class.name, message: error.message }.to_json)
  end

  # A run given up on an earlier try whose telling never happened. Telling once (Workflow::Run#claim_telling!) keeps it
  # from being said twice.
  def untold_give_up?(run) = run.reload.failed? && run.error == GAVE_UP && run.told_at.nil?

  def trigger_kind(workflow) = workflow.live_version.trigger[Workflow::Trigger::KEY_KIND]

  def payload(due_at) = { "due_at" => due_at.iso8601 }

  def start_key(due_at) = "trigger:#{due_at.utc.iso8601}"
end
