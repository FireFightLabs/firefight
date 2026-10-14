# Before a change a workflow makes when nobody pressed Run, or after an approval it waited for, Halon reads whether the
# problem it answers is still there, as whoever the run acts as, and hands the step its verdict and what it read.
class WorkflowStateCheckJob < ApplicationJob
  queue_as :investigations

  def perform(run_id, record_id, engine_step_id, key, named, asked)
    run = Workflow::Run.find_by(id: run_id)
    return unless run

    owner = Workflow::Run::Step.find_by(id: record_id) || run
    found = Workflow::NeedCheck.run(run: run, owner: owner, call: Workflow::NeedCheck::Call.new(named: named, asked: asked))
    DefinedWorkflow.deliver!(engine_step_id, key, { "verdict" => found.verdict, "state" => found.state })
  end
end
