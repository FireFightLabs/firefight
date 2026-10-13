require "test_helper"

class WorkflowVersionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    @workflow = Workflow.create!(workspace: @workspace, name: "Probe check")
    @workflow.edit!(operation: Workflow::Edit::OPERATION_ADD_STEP, by: @alice,
                    payload: { "step" => { "id" => "wait", "name" => "wait", "kind" => DefinedWorkflow::KIND_DELAY, "config" => { "minutes" => 5 } } })
    @draft = @workflow.reload.draft
    WorkspaceAdapter.stubs(:for).returns(stub(update_workflow_publish_request: { success: true }, post_workflow_publish_answer_to_user: { channel_id: "D", message_id: "1" }))
  end

  test "an admin publishes the draft as it was seen and it says so" do
    sign_in(users(:alice), @workspace)

    post publish_workflow_path(@workflow), params: { revision: @draft.revision }, as: :json

    assert_equal "Probe check was published.", flash[:notice]
    assert_equal @draft, @workflow.reload.live_version
  end

  test "a draft changed since the admin looked is not published" do
    sign_in(users(:alice), @workspace)

    post publish_workflow_path(@workflow), params: { revision: 0 }, as: :json

    assert_equal "Someone changed the draft since you looked, so look again before publishing.", flash[:alert]
    assert_nil @workflow.reload.live_version
  end

  test "a member cannot publish, and is told how to get it published" do
    sign_in(users(:bob), @workspace)

    post publish_workflow_path(@workflow), params: { revision: @draft.revision }, as: :json

    assert_match "permission", flash[:alert]
    assert_nil @workflow.reload.live_version
  end

  test "restoring with a draft open is refused, and restoring once it is published makes a new draft" do
    @draft.publish!(by: @alice)
    @workflow.reload.edit!(operation: Workflow::Edit::OPERATION_CHANGE_CONFIG, by: @alice, payload: { "step_id" => "wait", "changes" => { "config" => { "minutes" => 9 } } })
    sign_in(users(:bob), @workspace)

    post workflow_version_restore_path(@workflow, @draft), as: :json
    assert_equal "Publish or discard the open draft first.", flash[:alert]

    post workflow_version_discard_path(@workflow, @workflow.reload.draft), as: :json
    assert_equal "The draft of Probe check was discarded.", flash[:notice]

    post workflow_version_restore_path(@workflow, @draft), as: :json
    assert_equal "Version 1 was restored as draft version 3.", flash[:notice]
    assert_equal({ "minutes" => 5 }, @workflow.reload.draft.steps.sole["config"])
  end
end
