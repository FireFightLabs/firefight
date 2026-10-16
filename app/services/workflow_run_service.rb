# Starts a run of a workflow: refuses what may not start, keeps the run's record and starts the engine on the version's
# snapshot. Every way a run starts goes through here, by hand, from Halon, from a trigger, from another workflow or again
# from a step of an earlier run, so none of them can skip the workflows flag or the workflow's limits. One start key
# gives one run.
class WorkflowRunService
  def initialize(workflow)
    @workflow = workflow
  end

  # inputs are what a person gave for the trigger's questions, each left out taken from its default. A run waits for
  # not_before when given. A test run runs the draft (or the live version when there is none) as the person testing,
  # makes no change but the ones they turned on (real_step_keys), takes each output pinned on that version in place of
  # its step, and counts against no limit. up_to tries one step with only the steps before it, each standing in with
  # what it gave in the newest run that reached it when it has no pin. stand_ins and snapshot are what a run started again
  # from a later step takes from the run it came from (rerun_from!).
  def start!(started_by_kind:, started_by: nil, inputs: {}, trigger_kind: Workflow::Trigger::KIND_MANUAL, trigger_payload: {},
             start_key: SecureRandom.uuid, not_before: nil, parent_run: nil, parent_step: nil, test: false, real_step_keys: [],
             up_to: nil, stand_ins: {}, snapshot: nil, rerun_of: nil, rerun_from_step_key: nil)
    version = test ? tested_version(up_to) : live_version
    content = snapshot || (up_to.present? ? version.snapshot_up_to(up_to) : nil)
    resolved = Workflow::Trigger.resolve_inputs(version.trigger, inputs, private_values: version.private_input_values)
    plain, kept = Workflow::Trigger.split_private(version.trigger, resolved.values)
    refuse!("#{@workflow.name} needs a value for #{resolved.missing.map { |input| input['key'] }.to_sentence}.") if resolved.missing.any?
    payload = Workflow::Run.redacted(trigger_payload.to_h)
    subject = @workflow.subject_for(inputs: plain, trigger_payload: payload)
    standing = test ? earlier_results(version, content, up_to).merge(version.pinned_stand_ins(content || version.snapshot)).merge(stand_ins) : stand_ins

    run = Workflow.transaction do
      refuse_limits! unless test
      refuse!(already_running(subject)) if subject && @workflow.runs.unfinished.exists?(subject_key: subject)

      open_run(
        start_key, version: version, status: Workflow::Run::STATUS_QUEUED, trigger_kind: trigger_kind, trigger_payload: payload,
                   inputs: Workflow::Run.redacted(plain), private_inputs: (kept.to_json if kept.any?), agent: @workflow.agent,
                   started_by_kind: started_by_kind, started_by: started_by, parent_run: parent_run, parent_step_key: parent_step&.name, test: test,
                   real_step_keys: test ? real_keys(version, content, real_step_keys) : [], subject_key: subject,
                   snapshot: content, stand_ins: standing, rerun_of: rerun_of, rerun_from_step_key: rerun_from_step_key
      )
    end
    DefinedWorkflow.launch!(run, not_before: not_before, parent_step: parent_step)
    Conversation::Workflows.moved!(@workflow) unless test
    run
  end

  # Starts a run again from one of its steps, on the same inputs and trigger. Each step before it that succeeded stands
  # in with what it gave, and that step and every one after it runs again. A test run starts again as a test run of the
  # draft, a real one as a real run of the live version, so a fix published since is what runs.
  def self.rerun_from!(source, step_key:, by:)
    row = source.steps.find_by(step_key: step_key, iteration: "") || raise(Workflow::Run::Refused, "That step is not part of the run.")
    blocked = row.rerun_blocked_reason
    raise Workflow::Run::Refused, blocked if blocked

    workflow = source.workflow
    version = source.test? ? (workflow.draft || workflow.live_version) : workflow.live_version
    raise Workflow::Run::Refused, "#{workflow.name} has no version to run." unless version

    again = version.descendants_of(step_key) + [ step_key ]
    stand_ins = source.steps.where(iteration: "", status: Workflow::Run::Step::STATUS_SUCCEEDED).where.not(step_key: again)
                      .to_h { |step| [ step.step_key, { Workflow::Run::Testing::KEY_OUTPUT => step.output.to_h, Workflow::Run::Testing::KEY_ROUTE => step.route }.compact ] }
    new(workflow).start!(
      started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: by, inputs: source.inputs.merge(source.private_input_values), trigger_kind: source.trigger_kind,
      trigger_payload: source.trigger_payload, test: source.test?, real_step_keys: source.real_step_keys, stand_ins: stand_ins,
      snapshot: (source.ran_snapshot if source.test?), rerun_of: source, rerun_from_step_key: step_key
    )
  end

  # A run_workflow step starting the workflow it names, in the same workspace, once per step. Inside a test run the
  # workflow it runs is tried too, as the same tester, so nothing it would change is changed.
  def self.start_called!(parent_run:, step:, workflow_named:, inputs:)
    target = Workflow.named(Workflow.where(workspace_id: parent_run.workspace_id), workflow_named)
    raise Workflow::Run::Refused, "No workflow is called #{workflow_named}." unless target

    new(target).start!(started_by_kind: parent_run.test? ? Workflow::Run::STARTED_BY_PERSON : Workflow::Run::STARTED_BY_WORKFLOW,
                       started_by: (parent_run.started_by if parent_run.test?), trigger_kind: Workflow::Trigger::KIND_CALLED, inputs: inputs,
                       trigger_payload: { "workflow" => parent_run.workflow.name, "run_id" => parent_run.id },
                       start_key: "#{parent_run.id}:#{step.id}", parent_run: parent_run, parent_step: step, test: parent_run.test?)
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

  # Trying one step asks only that it and the steps before it can run.
  def tested_version(up_to)
    refuse!("Workflows are not switched on for this workspace.") unless FeatureFlags.enabled?(@workflow.workspace, FeatureFlags::WORKFLOWS)
    version = @workflow.draft || @workflow.live_version
    refuse!("#{@workflow.name} has no steps to test yet.") unless version && version.steps.any?
    problem = DefinedWorkflow.problems(up_to.present? ? version.snapshot_up_to(up_to) : version.snapshot).first
    refuse!("It cannot be tested yet. #{problem}") if problem
    version
  end

  # Counted with the workflow locked until the run is made, so starts at once cannot each see room for one more.
  def refuse_limits!
    Workflow.find(@workflow.id).lock!
    over = @workflow.rate_blocked_reason
    raise Workflow::Run::OverHourLimit, over if over
  end

  # Only steps of what runs that change something can be made for real, by their stable id.
  def real_keys(version, content, keys)
    runs = Workflow::Version.all_steps((content || version.snapshot)["steps"]).map { |step| step["id"] }
    changing = version.steps_that_change.map { |step| step["id"] } & runs
    Array(keys).map(&:to_s) & changing
  end

  # For one step tried alone: what each step before it gave in the newest run of the workflow that reached it.
  def earlier_results(version, content, up_to)
    return {} if up_to.blank? || content.nil?

    wanted = content["steps"].map { |step| step["id"] } - [ version.top_level_id(up_to) ]
    Workflow::Run::Step.joins(:run).where(workflow_runs: { workflow_id: @workflow.id }, step_key: wanted, iteration: "",
                                          status: Workflow::Run::Step::STATUS_SUCCEEDED)
                       .order("workflow_run_steps.finished_at DESC").to_a.uniq(&:step_key)
                       .to_h { |step| [ step.step_key, { Workflow::Run::Testing::KEY_OUTPUT => step.output.to_h, Workflow::Run::Testing::KEY_ROUTE => step.route }.compact ] }
  end

  def already_running(subject) = "#{@workflow.name} is already running for #{subject}, so this run did not start."

  def refuse!(reason)
    raise Workflow::Run::Refused, reason if reason
  end
end
