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
  ON_FAILURE_CONTINUE = SolidWorkflow::Definition::ON_FAILURE_CONTINUE
  ON_FAILURE_ERROR_ROUTE = SolidWorkflow::Definition::ON_FAILURE_ERROR_ROUTE
  CONDITION_EQUALS = SolidWorkflow::Condition::OPERATOR_EQUALS
  CONDITION_ANY = SolidWorkflow::Condition::ANY
  # The engine's run states, as a run's record reads them.
  RUN_STATUSES = {
    SolidWorkflow::Workflow.states.fetch("pending") => Workflow::Run::STATUS_QUEUED,
    SolidWorkflow::Workflow.states.fetch("running") => Workflow::Run::STATUS_RUNNING,
    SolidWorkflow::Workflow.states.fetch("waiting") => Workflow::Run::STATUS_WAITING,
    SolidWorkflow::Workflow.states.fetch("paused") => Workflow::Run::STATUS_PAUSED,
    SolidWorkflow::Workflow.states.fetch("succeeded") => Workflow::Run::STATUS_SUCCEEDED,
    SolidWorkflow::Workflow.states.fetch("failed") => Workflow::Run::STATUS_FAILED,
    SolidWorkflow::Workflow.states.fetch("cancelled") => Workflow::Run::STATUS_CANCELLED
  }.freeze
  START_KEY_PREFIX = "workflow_run:".freeze
  # The error's class, as the engine writes it ahead of the words, which a person reading why a step failed never needs.
  ERROR_CLASS = /\A[A-Z][\w:]*: /

  class << self
    def action_kinds = DefinedWorkflow::Steps.action_kinds

    # Runs one step of a kind the app defines, as the run's own step.
    def perform(kind, config, workflow:, step:)
      definition = DefinedWorkflow::Steps.for(kind)
      run = run_of(workflow)
      raise SolidWorkflow::UnknownStepKind, "No step of kind #{kind.inspect} can run" unless definition && run

      definition.new(run: run, step: step, config: config).perform
    end

    # Which item of which for each a run of the engine is, as the run's record keys its step rows.
    def iteration_of(workflow) = Array(workflow.context.to_h[CONTEXT_ITERATION]).join(".")

    # Notes that a step handed off work under this name, once, in one statement. False when it already had.
    def mark_asked!(step, name)
      sql = <<~SQL.squish
        checkpoint = jsonb_set(COALESCE(checkpoint, '{}'::jsonb), '{#{DefinedWorkflow::Steps::Base::CHECKPOINT_ASKED}}',
          COALESCE(checkpoint -> '#{DefinedWorkflow::Steps::Base::CHECKPOINT_ASKED}', '{}'::jsonb) || jsonb_build_object(?::text, true))
      SQL
      SolidWorkflow::Step.where(id: step.id).where("COALESCE(checkpoint, '{}'::jsonb) -> ? -> ? IS NULL", DefinedWorkflow::Steps::Base::CHECKPOINT_ASKED, name)
                         .update_all([ "#{sql}, updated_at = ?", name, Time.current ]) == 1
    end

    # Hands a step what the work it waited for came back with, once, and wakes it. A step still running when it lands
    # wakes itself as soon as it parks. False when the step is gone or already had it.
    def deliver!(step_id, name, payload)
      step = SolidWorkflow::Step.find_by(id: step_id)
      return false unless step

      kept = clean(payload.to_h.deep_stringify_keys, workflow: step.workflow, step: step)
      key = DefinedWorkflow::Steps::Base::CHECKPOINT_DELIVERED
      sql = "checkpoint = jsonb_set(COALESCE(checkpoint, '{}'::jsonb), '{#{key}}', COALESCE(checkpoint -> '#{key}', '{}'::jsonb) || jsonb_build_object(?::text, ?::jsonb))"
      delivered = SolidWorkflow::Step.where(id: step.id).where("COALESCE(checkpoint, '{}'::jsonb) -> ? -> ? IS NULL", key, name)
                                     .update_all([ "#{sql}, updated_at = ?", name, kept.to_json, Time.current ]) == 1
      step.wake!(reason: "delivered") if delivered
      delivered
    end

    # The same, for a step known by its row on the run's record, such as a watch it started that just ended.
    def deliver_for_record!(record, name, payload)
      step = SolidWorkflow::Step.joins(:workflow).where(name: record.step_key)
                                .where(solid_workflow_workflows: { subject_type: Workflow::Run.name, subject_id: record.run_id })
                                .includes(:workflow).find { |candidate| iteration_of(candidate.workflow) == record.iteration }
      step ? deliver!(step.id, name, payload) : false
    end

    # A step's error as a person reads it: its first line, without the class the engine writes ahead of it.
    def error_words(error) = error.to_s.lines.first.to_s.strip.sub(ERROR_CLASS, "")
    # Starts the engine's run for a run record, once however often it is asked.
    def launch!(run, not_before: nil, parent_step: nil)
      start!(run, definition: run.version.snapshot, start_key: start_key_for(run), not_before: not_before, parent_step: parent_step,
                  context: { SCOPE_INPUTS => run.inputs, SCOPE_TRIGGER => run.trigger_payload })
    end

    def start_key_for(run) = "#{START_KEY_PREFIX}#{run.id}"

    # Ends a run that is still going, with every step and run it started. False when it had ended.
    def cancel!(run, by:)
      engine = SolidWorkflow::Workflow.find_by(start_key: start_key_for(run))
      engine.present? && engine.cancel!(reason: "cancelled_by_person", by: by&.actor_display_name)
    end

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

      moved = run.record_status!(RUN_STATUSES.fetch(workflow.state), step_started: step.present?, outputs: workflow.result, error: failure_of(workflow))
      ActiveRecord.after_all_transactions_commit { WorkflowRunEndedJob.perform_later(run.id) } if moved && run.finished?
    end

    private

    def run_of(workflow) = workflow.subject.is_a?(Workflow::Run) ? workflow.subject : nil

    # A step that acts is tried once unless its own retry says otherwise, since doing a change again on its own is a
    # person's decision.
    def default_retry_config = { max_attempts: 1, backoff: SolidWorkflow::Step::Retryable::BACKOFF_EXPONENTIAL }

    def record_step(run, workflow, step)
      run.record_step!(
        step_key: step.name, iteration: Array(workflow.context.to_h[CONTEXT_ITERATION]).join("."), name: step.label, kind: step.kind,
        status: step.status, route: step.route, input: step.input, output: step.output.presence,
        saved_result_ids: [ step.input, step.output ].filter_map { |data| data.to_h.dig(Workflow::Run::Data::KEY_SAVED_RESULT, "id") },
        attempts: step.attempts, error: step.failed? ? error_words(step.last_error) : nil, started_at: step.first_started_at,
        finished_at: step.completed? ? step.completed_at : nil
      )
    end

    # A run's own moves, starting, waiting or ending, can move steps all at once without an event each, such as
    # cancelling the rest, so each writes every step.
    def sync_all_steps(run, workflow) = workflow.steps.reload.each { |step| record_step(run, workflow, step) }

    def failure_of(workflow)
      return unless workflow.failed?

      stopped = workflow.steps.select(&:failed?).reject(&:failure_tolerated?).min_by(&:completed_at)
      stopped ? "#{stopped.label} failed. #{error_words(stopped.last_error)}" : "The run ran past its time limit."
    end
  end
end
