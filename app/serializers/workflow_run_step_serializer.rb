# What one step of a run did, as the run's view on the canvas shows it: its state and time, what it was given and gave,
# the results it kept whole, every gateway call it made with how each was decided and ended, its error, and why it cannot
# be tried again, skipped or started again from.
class WorkflowRunStepSerializer < BaseSerializer
  object_as :step

  type :string
  def id
    step.id
  end

  type :string
  def step_key
    step.step_key
  end

  # The item's place in each for each it sits in, empty for a step at the top.
  type :string
  def iteration
    step.iteration
  end

  type "#{Workflow::Run::Step::STATUSES.map(&:inspect).join(' | ')}"
  def status
    step.status
  end

  type :string, optional: true
  def route
    step.route
  end

  type "Record<string, unknown>", optional: true
  def input
    step.input
  end

  type "Record<string, unknown>", optional: true
  def output
    step.output
  end

  type "{ id: string; handle: string; bytes: number | null }[]"
  def saved_results
    step.saved_results.map { |result| { id: result.id, handle: result.handle, bytes: result.content&.bytesize } }
  end

  # The pages a Browser step saw, one per screen size, each served from the run's view.
  type "{ id: string; caption: string; url: string }[]"
  def screenshots
    shots = step.chat&.screenshots&.in_order.to_a
    shots.map do |shot|
      { id: shot.id, caption: shot.caption,
        url: Rails.application.routes.url_helpers.workflow_run_screenshot_path(step.run.workflow_id, step.run_id, shot) }
    end
  end

  type :number
  def attempts
    step.attempts
  end

  type :string, optional: true
  def error
    step.error
  end

  type :string, optional: true
  def started_at
    step.started_at&.iso8601
  end

  type :string, optional: true
  def finished_at
    step.finished_at&.iso8601
  end

  # An output pinned on the draft or kept from the run it started again from stood in, so the step did not run.
  type :boolean
  def stood_in
    step.top_level? && step.run.stood_in?(step.step_key)
  end

  # A change a test run only showed rather than made (DefinedWorkflow::Steps::Base#simulated_output).
  type :boolean
  def simulated
    step.output.to_h[DefinedWorkflow::Steps::Base::OUTPUT_SIMULATED] == true
  end

  type :boolean
  def waiting_approval
    step.waiting_approval?
  end

  type "{ id: string; actionKey: string; decision: #{Ability::Invocation::DECISIONS.map(&:inspect).join(' | ')}; outcome: string | null; errorSummary: string | null; durationMs: number | null; approvalStatus: string | null; createdAt: string }[]"
  def invocations
    step.invocations.map do |call|
      { id: call.id, actionKey: call.action_key, decision: call.decision, outcome: call.outcome, errorSummary: call.error_summary,
        durationMs: call.duration_ms, approvalStatus: call.approval&.status, createdAt: call.created_at.iso8601 }
    end
  end

  type :string, optional: true
  def retry_blocked_reason
    step.retry_blocked_reason
  end

  type :string, optional: true
  def skip_blocked_reason
    step.skip_blocked_reason
  end

  type :string, optional: true
  def rerun_blocked_reason
    step.rerun_blocked_reason
  end
end
