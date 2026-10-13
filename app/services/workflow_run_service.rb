# Starts a run of a workflow: refuses what may not start, keeps the run's record and starts the engine on the version's
# snapshot. Every way a run starts goes through here, by hand, from Halon, from a trigger or from another workflow, so
# none of them can skip the workflows flag or the workflow's limits. One start key gives one run.
class WorkflowRunService
  def initialize(workflow)
    @workflow = workflow
  end

  # inputs are what a person gave for the trigger's questions, each left out taken from its default. A run waits for
  # not_before when given. A test run runs the draft (or the live version when there is none) as the person testing,
  # makes no change but the ones they turned on (real_step_keys), and counts against no limit.
  def start!(started_by_kind:, started_by: nil, inputs: {}, trigger_kind: Workflow::Trigger::KIND_MANUAL, trigger_payload: {},
             start_key: SecureRandom.uuid, not_before: nil, parent_run: nil, parent_step: nil, test: false, real_step_keys: [])
    version = test ? tested_version : live_version
    resolved = Workflow::Trigger.resolve_inputs(version.trigger, inputs, private_values: @workflow.private_input_values)
    plain, kept = Workflow::Trigger.split_private(version.trigger, resolved.values)
    refuse!("#{@workflow.name} needs a value for #{resolved.missing.map { |input| input['key'] }.to_sentence}.") if resolved.missing.any?
    payload = Workflow::Run.redacted(trigger_payload.to_h)
    subject = @workflow.subject_for(inputs: plain, trigger_payload: payload)

    run = Workflow.transaction do
      refuse_limits!(trigger_kind) unless test
      refuse!(already_running(subject)) if subject && @workflow.runs.unfinished.exists?(subject_key: subject)

      open_run(
        start_key, version: version, status: Workflow::Run::STATUS_QUEUED, trigger_kind: trigger_kind, trigger_payload: payload,
                   inputs: Workflow::Run.redacted(plain), private_inputs: (kept.to_json if kept.any?), agent: @workflow.agent, started_by_kind: started_by_kind, started_by: started_by,
                   parent_run: parent_run, parent_step_key: parent_step&.name, test: test, real_step_keys: test ? real_keys(version, real_step_keys) : [],
                   subject_key: subject
      )
    end
    DefinedWorkflow.launch!(run, not_before: not_before, parent_step: parent_step)
    Conversation::Workflows.moved!(@workflow) unless test
    run
  end

  # A run_workflow step starting the workflow it names, in the same workspace, once per step.
  def self.start_called!(parent_run:, step:, workflow_named:, inputs:)
    target = Workflow.named(Workflow.where(workspace_id: parent_run.workspace_id), workflow_named)
    raise Workflow::Run::Refused, "No workflow is called #{workflow_named}." unless target

    new(target).start!(started_by_kind: Workflow::Run::STARTED_BY_WORKFLOW, trigger_kind: Workflow::Trigger::KIND_CALLED, inputs: inputs,
                       trigger_payload: { "workflow" => parent_run.workflow.name, "run_id" => parent_run.id },
                       start_key: "#{parent_run.id}:#{step.id}", parent_run: parent_run, parent_step: step)
  end

  private

  # A run of the same subject that started in between wins the one live run per subject, and this start is refused.
  def open_run(start_key, **attributes)
    run, = Workflow::Run.open!(workflow: @workflow, start_key: start_key, **attributes)
    run
  rescue ActiveRecord::RecordNotFound
    refuse!(already_running(attributes[:subject_key]))
  end

  def live_version
    refuse!(@workflow.start_blocked_reason)
    @workflow.live_version
  end

  def tested_version
    refuse!("Workflows are not switched on for this workspace.") unless FeatureFlags.enabled?(@workflow.workspace, FeatureFlags::WORKFLOWS)
    version = @workflow.draft || @workflow.live_version
    refuse!("#{@workflow.name} has no steps to test yet.") unless version && version.steps.any?
    problem = DefinedWorkflow.problems(version.snapshot).first
    refuse!("It cannot be tested yet. #{problem}") if problem
    version
  end

  # Counted with the workflow locked, and the workspace too for an event, until the run is made, so starts at once
  # cannot each see room for one more.
  def refuse_limits!(trigger_kind)
    event = !Workflow::Limits::NOT_EVENTS.include?(trigger_kind)
    Workflow.find(@workflow.id).lock!
    Workspace.find(@workflow.workspace_id).lock! if event
    refuse!(@workflow.rate_blocked_reason)
    refuse!(Workflow.event_blocked_reason(@workflow.workspace)) if event
  end

  # Only steps of the version that change something can be made for real, by their stable id.
  def real_keys(version, keys)
    changing = version.steps_that_change.map { |step| step["id"] }
    Array(keys).map(&:to_s) & changing
  end

  def already_running(subject) = "#{@workflow.name} is already running for #{subject}, so this run did not start."

  def refuse!(reason)
    raise Workflow::Run::Refused, reason if reason
  end
end
