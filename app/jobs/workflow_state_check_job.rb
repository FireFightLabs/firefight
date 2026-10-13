# Halon reads how things stand before a change a workflow makes when nobody pressed Run, or after an approval it waited
# for, as whoever the run acts as, and hands the step what it read. The step stops unless nothing moved.
class WorkflowStateCheckJob < ApplicationJob
  queue_as :investigations

  def perform(run_id, record_id, engine_step_id, key, named, asked)
    run = Workflow::Run.find_by(id: run_id)
    return unless run

    owner = Workflow::Run::Step.find_by(id: record_id) || run
    report = Chat::StateCheck.run(
      owner: owner, workspace: run.workspace, principal: run.acting_principal, source: AbilityGateway::SOURCE_WORKFLOW,
      call: Chat::StateCheck::Call.new(named: named, asked: asked, approved_by: "#{run.workflow.name}, a workflow,"),
      ledger: { triggered_by_label: run.ledger_label, **Workflow::Run::Step.ledger_context(run, owner.is_a?(Workflow::Run::Step) ? owner : nil) }.compact
    )
    DefinedWorkflow.deliver!(engine_step_id, key, { "state" => report.state, "change" => report.change })
  end
end
