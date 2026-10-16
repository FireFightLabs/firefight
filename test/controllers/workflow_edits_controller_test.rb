require "test_helper"

class WorkflowEditsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @workflow = Workflow.create!(workspace: @workspace, name: "Probe check")
  end

  def delay(id) = { "id" => id, "name" => id, "kind" => DefinedWorkflow::KIND_DELAY, "config" => { "minutes" => 5 } }

  def draft = @workflow.reload.draft

  test "a member adds, sets up, connects, moves and removes steps on the draft, each saying so" do
    sign_in(users(:bob), @workspace)

    post workflow_edits_path(@workflow), params: { operation: Workflow::Edit::OPERATION_ADD_STEP, payload: { step: delay("check_logs") } }, as: :json
    assert_equal "Check logs was added.", flash[:notice]
    post workflow_edits_path(@workflow), params: { operation: Workflow::Edit::OPERATION_ADD_STEP, payload: { step: delay("tell") }, base_revision: 1 }, as: :json
    post workflow_edits_path(@workflow), params: { operation: Workflow::Edit::OPERATION_CONNECT, payload: { from: "check_logs", to: "tell" }, base_revision: 2 },
                                         as: :json
    assert_equal "Check logs now leads to Tell.", flash[:notice]
    post workflow_edits_path(@workflow), as: :json,
                                         params: { operation: Workflow::Edit::OPERATION_CHANGE_CONFIG, base_revision: 3,
                                                   payload: { step_id: "tell", changes: { config: { minutes: 10 }, timeout_seconds: 120 } } }
    assert_equal "Tell was updated.", flash[:notice]
    post workflow_edits_path(@workflow), params: { operation: Workflow::Edit::OPERATION_MOVE_STEP, payload: { step_id: "tell", position: { x: 40, y: 200 } } },
                                         as: :json
    assert_equal "Tell was moved.", flash[:notice]
    post workflow_edits_path(@workflow), params: { operation: Workflow::Edit::OPERATION_REMOVE_STEP, payload: { step_id: "check_logs" } }, as: :json
    assert_equal "Check logs was removed.", flash[:notice]

    assert_redirected_to workflow_path(@workflow)
    tell = draft.steps.sole
    assert_equal [ { "minutes" => 10 }, 120, { "x" => 40, "y" => 200 } ], tell.values_at("config", "timeout_seconds", "position")
    assert_equal [ workspace_memberships(:bob_workspace_one) ], @workflow.edits.map(&:author).uniq
  end

  test "renaming the workflow says so" do
    sign_in(users(:bob), @workspace)

    post workflow_edits_path(@workflow), params: { operation: Workflow::Edit::OPERATION_RENAME, payload: { name: "Weekday probe check" } }, as: :json

    assert_equal "The workflow was renamed to Weekday probe check.", flash[:notice]
    assert_equal "Weekday probe check", @workflow.reload.name
  end

  test "a change to a step someone changed since the person looked is refused with who changed it" do
    @workflow.edit!(operation: Workflow::Edit::OPERATION_ADD_STEP, payload: { "step" => delay("wait") }, by: @alice)
    @workflow.edit!(operation: Workflow::Edit::OPERATION_CHANGE_CONFIG, payload: { "step_id" => "wait", "changes" => { "config" => { "minutes" => 9 } } },
                    by: @alice, base_revision: 1)
    sign_in(users(:bob), @workspace)

    post workflow_edits_path(@workflow), as: :json,
                                         params: { operation: Workflow::Edit::OPERATION_CHANGE_CONFIG, base_revision: 1,
                                                   payload: { step_id: "wait", changes: { config: { minutes: 1 } } } }

    assert_equal "Alice Smith changed this since you looked, so look again before changing it.", flash[:alert]
    assert_equal({ "minutes" => 9 }, draft.steps.sole["config"])
  end

  test "a change no workflow takes is refused in words" do
    sign_in(users(:bob), @workspace)

    post workflow_edits_path(@workflow), params: { operation: "paint", payload: {} }, as: :json

    assert_equal "That is not a change a workflow takes.", flash[:alert]
  end
end
