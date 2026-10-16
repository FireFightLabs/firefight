require "test_helper"

class WorkflowHalonStepJobTest < ActiveJob::TestCase
  test "an error nobody expected is handed to the step in words, so the run does not wait out its time" do
    workspace = workspaces(:slack_workspace_one)
    alice = workspace_memberships(:alice_workspace_one)
    workflow = Workflow.create!(workspace: workspace, name: "Judge", created_by: alice)
    workflow.open_draft!(by: alice).update!(steps: [ { "id" => "judge", "name" => "judge", "kind" => "ask_halon", "config" => { "question" => "Fine?", "data" => "ok" } } ])
    WorkflowPublishService.new(workflow).publish!(workflow.draft, by: alice)
    run = WorkflowRunService.new(workflow.reload).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: alice)
    Workflow::HalonStep.any_instance.stubs(:ask!).raises(NoMethodError, "undefined method for nil")
    DefinedWorkflow.expects(:deliver!).with("engine-step", "handed_off#try2", { Workflow::HalonStep::KEY_ERROR => "Halon could not answer because of an error in Firefight." })

    WorkflowHalonStepJob.perform_now(run.id, nil, "engine-step", DefinedWorkflow::Steps::AskHalon.kind, { "question" => "Fine?" }, "handed_off#try2")
  end
end
