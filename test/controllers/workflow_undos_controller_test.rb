require "test_helper"

class WorkflowUndosControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @workflow = Workflow.create!(workspace: @workspace, name: "Probe check")
  end

  def delay(id) = { "id" => id, "name" => id, "kind" => DefinedWorkflow::KIND_DELAY, "config" => { "minutes" => 5 } }

  test "Halon's change is undone as a person's edits, keeping what people did around it" do
    @workflow.edit!(operation: Workflow::Edit::OPERATION_ADD_STEP, payload: { "step" => delay("wait") }, by: nil, halon: true, reason: "Wait first.")
    @workflow.edit!(operation: Workflow::Edit::OPERATION_ADD_STEP, payload: { "step" => delay("check") }, by: @alice)
    halon = @workflow.edits.find_by!(author_kind: Workflow::AUTHOR_HALON)
    sign_in(users(:bob), @workspace)

    post workflow_undo_path(@workflow), params: { edit_id: halon.id }, as: :json

    assert_equal "Halon's change was undone.", flash[:notice]
    assert_equal [ "check" ], @workflow.reload.draft.steps.map { |step| step["id"] }
    undo = @workflow.edits.order(:created_at).last
    assert_equal [ workspace_memberships(:bob_workspace_one), Workflow::Editing::UNDO_REASON ], [ undo.author, undo.reason ]
  end

  test "a change of a person's cannot be undone here" do
    @workflow.edit!(operation: Workflow::Edit::OPERATION_ADD_STEP, payload: { "step" => delay("check") }, by: @alice)
    sign_in(users(:bob), @workspace)

    post workflow_undo_path(@workflow), params: { edit_id: @workflow.edits.sole.id }, as: :json

    assert_equal "Choose a change of Halon's to undo.", flash[:alert]
  end
end
