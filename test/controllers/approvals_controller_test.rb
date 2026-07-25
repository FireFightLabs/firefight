require "test_helper"

class ApprovalsControllerTest < ActionDispatch::IntegrationTest
  fixtures :workspaces, :users, :workspace_memberships, :api_keys

  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
    @approval = Ability::Approval.create!(
      workspace: @workspace, principal: api_keys(:full_access_key),
      principal_label: api_keys(:full_access_key).principal_label,
      action_key: "catalog.delete", request_digest: Ability::Approval.digest("catalog.delete", {}, {}),
      required_role: WorkspaceMembership.roles[:admin]
    )
  end

  test "index lists pending approvals" do
    get approvals_url

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [ @approval.id ], body["approvals"].map { |a| a["id"] }
  end

  test "approve resolves the approval" do
    post approve_approval_url(@approval)

    assert_response :success
    assert @approval.reload.approved?
  end

  test "deny requires the policy role" do
    sign_in(users(:bob), @workspace)

    post deny_approval_url(@approval)

    assert_response :unprocessable_entity
    assert @approval.reload.pending?
  end

  private

  def sign_in(user, workspace)
    ApplicationController.any_instance.stubs(:current_user).returns(user)
    ApplicationController.any_instance.stubs(:current_workspace).returns(workspace)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
  end
end
