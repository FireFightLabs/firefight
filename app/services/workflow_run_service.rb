# Starts a run of a workflow: refuses what may not start, keeps the run's record and starts the engine on the live
# version's snapshot. Every way a run starts goes through here, by hand, from Halon, from a trigger or from another
# workflow, so none of them can skip the workflows flag. One start key gives one run.
class WorkflowRunService
  def initialize(workflow)
    @workflow = workflow
  end

  # inputs are what a person gave for the trigger's questions, each left out taken from its default. A run waits for
  # not_before when given.
  def start!(started_by_kind:, started_by: nil, inputs: {}, trigger_kind: Workflow::Trigger::KIND_MANUAL, trigger_payload: {},
             start_key: SecureRandom.uuid, not_before: nil, parent_run: nil, parent_step: nil)
    refuse!(@workflow.start_blocked_reason)
    version = @workflow.live_version
    resolved = Workflow::Trigger.resolve_inputs(version.trigger, inputs)
    refuse!("#{@workflow.name} needs a value for #{resolved.missing.map { |input| input['key'] }.to_sentence}.") if resolved.missing.any?

    run, = Workflow::Run.open!(
      workflow: @workflow, start_key: start_key, version: version, status: Workflow::Run::STATUS_QUEUED,
      trigger_kind: trigger_kind, trigger_payload: Workflow::Run.redacted(trigger_payload.to_h),
      inputs: Workflow::Run.redacted(resolved.values), agent: @workflow.agent,
      started_by_kind: started_by_kind, started_by: started_by, parent_run: parent_run, parent_step_key: parent_step&.name
    )
    DefinedWorkflow.launch!(run, not_before: not_before, parent_step: parent_step)
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

  def refuse!(reason)
    raise Workflow::Run::Refused, reason if reason
  end
end
