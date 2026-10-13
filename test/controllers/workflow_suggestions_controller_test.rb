require "test_helper"

class WorkflowSuggestionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    @workflow = Workflow.create!(workspace: @workspace, name: "Probe check")
    @workflow.edit!(operation: Workflow::Edit::OPERATION_ADD_STEP, by: @alice, payload: { "step" => delay("wait") })
    @workflow.reload.draft.publish!(by: @alice)
    @change_set = SecureRandom.uuid
    @first = suggest(Workflow::Edit::OPERATION_ADD_STEP, { "step" => delay("tell") })
    @second = suggest(Workflow::Edit::OPERATION_CONNECT, { "from" => "wait", "to" => "tell" })
  end

  def delay(id) = { "id" => id, "name" => id, "kind" => DefinedWorkflow::KIND_DELAY, "config" => { "minutes" => 5 } }

  def suggest(operation, payload)
    @workflow.reload.edit!(operation: operation, payload: payload, by: nil, halon: true, reason: "Tell someone once it waited.", change_set_id: @change_set)
  end

  test "one suggestion is accepted into a draft and says so" do
    sign_in(users(:bob), @workspace)

    post workflow_suggestion_accept_path(@workflow, @first), as: :json

    assert_equal "Halon's suggestion to add Tell was accepted.", flash[:notice]
    assert_equal %w[wait tell], @workflow.reload.draft.steps.map { |step| step["id"] }
    assert_equal workspace_memberships(:bob_workspace_one), @first.reload.decided_by
  end

  test "one suggestion is dismissed and the rest wait" do
    sign_in(users(:bob), @workspace)

    post workflow_suggestion_dismiss_path(@workflow, @second), as: :json

    assert_equal "Halon's suggestion to connect Wait to Tell was dismissed.", flash[:notice]
    assert_equal [ @first ], @workflow.proposals.to_a
  end

  test "every suggestion of a change is accepted at once, in the order Halon made them" do
    sign_in(users(:bob), @workspace)

    post workflow_suggestions_accept_path(@workflow), params: { change_set_id: @change_set }, as: :json

    assert_equal "2 of Halon's suggestions were accepted.", flash[:notice]
    assert_equal [ { "from" => "wait", "to" => "tell" } ], @workflow.reload.draft.edges
  end

  test "every suggestion is dismissed at once" do
    sign_in(users(:bob), @workspace)

    post workflow_suggestions_dismiss_path(@workflow), as: :json

    assert_equal "2 of Halon's suggestions were dismissed.", flash[:notice]
    assert_empty @workflow.proposals
  end

  test "a suggestion already decided is refused" do
    @first.dismiss!(by: @alice)
    sign_in(users(:bob), @workspace)

    post workflow_suggestion_accept_path(@workflow, @first), as: :json

    assert_response :not_found
  end
end
