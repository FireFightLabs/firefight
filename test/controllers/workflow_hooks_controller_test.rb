require "test_helper"

class WorkflowHooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @workflow = Workflow.create!(workspace: @workspace, name: "Deploy hook")
  end

  test "someone who may change the workflow reads its secret and replaces its address, which says so" do
    sign_in(users(:alice), @workspace)

    post workflow_hook_secret_path(@workflow), as: :json
    assert_response :success
    assert_equal @workflow.hook_secret, response.parsed_body["secret"]
    assert_equal @workflow.hook_url, response.parsed_body["url"]

    old = @workflow.hook_token
    post workflow_hook_replace_path(@workflow)
    assert_redirected_to workflow_path(@workflow)
    assert_equal "Deploy hook has a new webhook address and secret. The old ones no longer start it.", flash[:notice]
    assert_not_equal old, @workflow.reload.hook_token
  end

  test "a member who only builds drafts cannot read the secret or replace the address" do
    sign_in(users(:bob), @workspace)

    post workflow_hook_secret_path(@workflow), as: :json
    assert_response :redirect
    old = @workflow.hook_token
    post workflow_hook_replace_path(@workflow)
    assert_equal old, @workflow.reload.hook_token
  end
end
