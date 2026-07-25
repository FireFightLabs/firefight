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

  test "the approvals page lists pending and resolved approvals" do
    resolved = Ability::Approval.create!(
      workspace: @workspace, principal: api_keys(:full_access_key),
      principal_label: api_keys(:full_access_key).principal_label,
      action_key: "catalog.create", request_digest: Ability::Approval.digest("catalog.create", {}, {}),
      required_role: WorkspaceMembership.roles[:admin],
      status: Ability::Approval::STATUS_DENIED, resolved_at: Time.current
    )

    get settings_approvals_url

    assert_response :success
    assert_includes response.body, @approval.id
    assert_includes response.body, resolved.id
  end

  test "the activity page renders the ledger" do
    AbilityGateway.authorize!(principal: api_keys(:full_access_key), action_key: "catalog.create",
                              workspace: @workspace) { :ok }

    get settings_activity_url

    assert_response :success
    assert_includes response.body, "catalog.create"
  end

  test "approve resolves the approval and redirects" do
    post approve_approval_url(@approval)

    assert_redirected_to settings_approvals_path
    assert @approval.reload.approved?
  end

  test "deny without the required role redirects with the refusal" do
    sign_in(users(:bob), @workspace)

    post deny_approval_url(@approval)

    assert_redirected_to settings_approvals_path
    assert_equal "requires the admin role", flash[:alert]
    assert @approval.reload.pending?
  end

  private

  def sign_in(user, workspace)
    ApplicationController.any_instance.stubs(:current_user).returns(user)
    ApplicationController.any_instance.stubs(:current_workspace).returns(workspace)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
  end
end
