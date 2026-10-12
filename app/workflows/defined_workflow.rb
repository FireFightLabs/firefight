# Runs a workspace's workflows, each from the snapshot of the version its run started on. The engine runs the control
# steps, and this says how a reference is filled, what step data is kept, how a sub workflow starts and when a run may
# move: never for a workspace without the workflows flag. Every move the engine makes is written onto the run's own
# record (Workflow::Run), which outlives the engine's cleanup.
class DefinedWorkflow < SolidWorkflow::Interpreter
  workflow_name "workflow.defined.v1"

  KIND_BRANCH = SolidWorkflow::Definition::KIND_BRANCH
  KIND_DELAY = SolidWorkflow::Definition::KIND_DELAY
  KIND_WAIT_FOR_EVENT = SolidWorkflow::Definition::KIND_WAIT_FOR_EVENT
  KIND_FOR_EACH = SolidWorkflow::Definition::KIND_FOR_EACH
  KIND_JOIN = SolidWorkflow::Definition::KIND_JOIN
  KIND_RUN_WORKFLOW = SolidWorkflow::Definition::KIND_RUN_WORKFLOW
  STEP_KINDS = SolidWorkflow::Definition::CONTROL_KINDS
  BODY_KEYS = SolidWorkflow::Definition::BODY_KEYS
  SCOPE_INPUTS = SolidWorkflow::Interpreter::SCOPE_INPUTS
  SCOPE_TRIGGER = SolidWorkflow::Interpreter::SCOPE_TRIGGER
  SCOPE_STEPS = SolidWorkflow::Interpreter::SCOPE_STEPS
  SCOPE_ITEM = SolidWorkflow::Interpreter::SCOPE_ITEM
  SCOPE_INDEX = SolidWorkflow::Interpreter::SCOPE_INDEX
  CONTEXT_ITERATION = SolidWorkflow::Interpreter::CONTEXT_ITERATION
  STEP_STATUSES = SolidWorkflow::Step.statuses.keys.freeze
  # The engine's run states, as a run's record reads them. A run an operator paused waits for them.
  RUN_STATUSES = {
    SolidWorkflow::Workflow.states.fetch("pending") => Workflow::Run::STATUS_QUEUED,
    SolidWorkflow::Workflow.states.fetch("running") => Workflow::Run::STATUS_RUNNING,
    SolidWorkflow::Workflow.states.fetch("waiting") => Workflow::Run::STATUS_WAITING,
    SolidWorkflow::Workflow.states.fetch("paused") => Workflow::Run::STATUS_WAITING,
    SolidWorkflow::Workflow.states.fetch("succeeded") => Workflow::Run::STATUS_SUCCEEDED,
    SolidWorkflow::Workflow.states.fetch("failed") => Workflow::Run::STATUS_FAILED,
    SolidWorkflow::Workflow.states.fetch("cancelled") => Workflow::Run::STATUS_CANCELLED
  }.freeze
  START_KEY_PREFIX = "workflow_run:".freeze

  class << self
    # Starts the engine's run for a run record, once however often it is asked.
    def launch!(run, not_before: nil, parent_step: nil)
      start!(run, definition: run.version.snapshot, start_key: start_key_for(run), not_before: not_before, parent_step: parent_step,
                  context: { SCOPE_INPUTS => run.inputs, SCOPE_TRIGGER => run.trigger_payload })
    end

    def start_key_for(run) = "#{START_KEY_PREFIX}#{run.id}"

    def runnable?(workflow) = run_of(workflow)&.may_move? || false

    def resolve(value, scope, workflow:, step:) = Workflow::Version.filled(value, scope)

    def clean(data, workflow:, step:)
      run = run_of(workflow)
      run ? run.kept(data, step_name: step&.label) : Workflow::Run.redacted(data)
    end

    def start_sub_workflow(config, workflow:, step:)
      parent = run_of(workflow)
      child = WorkflowRunService.start_called!(parent_run: parent, step: step, workflow_named: config["workflow"], inputs: config["inputs"].to_h)
      SolidWorkflow::Workflow.find_by!(start_key: start_key_for(child))
    end

    def observe(workflow, event)
      run = run_of(workflow)
      return unless run

      step = event.step
      record_step(run, workflow, step) if step
      sync_all_steps(run, workflow) if step.nil?
      return unless workflow.start_key == start_key_for(run)

      run.record_status!(RUN_STATUSES.fetch(workflow.state), step_started: step.present?, outputs: workflow.result, error: failure_of(workflow))
    end

    private

    def run_of(workflow) = workflow.subject.is_a?(Workflow::Run) ? workflow.subject : nil

    def record_step(run, workflow, step)
      run.record_step!(
        step_key: step.name, iteration: Array(workflow.context.to_h[CONTEXT_ITERATION]).join("."), name: step.label, kind: step.kind,
        status: step.status, route: step.route, input: step.input, output: step.output.presence,
        saved_result_ids: [ step.input, step.output ].filter_map { |data| data.to_h.dig(Workflow::Run::Data::KEY_SAVED_RESULT, "id") },
        attempts: step.attempts, error: step.failed? ? step.last_error : nil, started_at: step.first_started_at,
        finished_at: step.completed? ? step.completed_at : nil
      )
    end

    # A run's own moves, starting, waiting or ending, can move steps all at once without an event each, such as
    # cancelling the rest, so each writes every step.
    def sync_all_steps(run, workflow) = workflow.steps.reload.each { |step| record_step(run, workflow, step) }

    def failure_of(workflow)
      return unless workflow.failed?

      stopped = workflow.steps.select(&:failed?).reject(&:failure_tolerated?).min_by(&:completed_at)
      stopped ? "#{stopped.label} failed. #{stopped.last_error.to_s.lines.first.to_s.strip}" : "The run ran past its time limit."
    end
  end
end
