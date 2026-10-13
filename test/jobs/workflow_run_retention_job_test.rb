require "test_helper"

class WorkflowRunRetentionJobTest < ActiveSupport::TestCase
  test "drops the details of runs past each workspace's retention" do
    workspace = workspaces(:slack_workspace_one)
    alice = workspace_memberships(:alice_workspace_one)
    workflow = Workflow.create!(workspace: workspace, name: "Check")
    draft = workflow.open_draft!(by: alice)
    draft.update!(steps: [ { "id" => "pause", "name" => "pause", "kind" => "delay", "config" => { "seconds" => 1 } } ])
    draft.publish!(by: alice)
    old, = Workflow::Run.open!(workflow: workflow, start_key: "old", version: workflow.reload.live_version, trigger_kind: Workflow::Trigger::KIND_MANUAL,
                               started_by_kind: Workflow::Run::STARTED_BY_PERSON, status: Workflow::Run::STATUS_CANCELLED, finished_at: 91.days.ago)

    WorkflowRunRetentionJob.perform_now

    assert old.reload.details_pruned?
    assert_equal Workflow::Run::STATUS_CANCELLED, old.status
  end
end
