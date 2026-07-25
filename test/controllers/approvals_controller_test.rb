require "test_helper"

class ApprovalsControllerTest < ActionDispatch::IntegrationTest
  fixtures :workspaces, :users, :workspace_memberships, :api_keys, :ability_actions, :ability_grants

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

    get settings_approvals_url, headers: inertia_headers

    assert_response :success
    assert_equal [ @approval.id ], inertia_props["pendingApprovals"].map { |a| a["id"] }
    assert_equal [ resolved.id ], inertia_props["resolvedApprovals"].map { |a| a["id"] }
  end

  test "the activity page renders the ledger" do
    AbilityGateway.authorize!(principal: api_keys(:full_access_key), action_key: "catalog.create",
                              workspace: @workspace) { :ok }

    get settings_activity_url, headers: inertia_headers

    assert_response :success
    assert_equal [ "catalog.create" ], inertia_props["invocations"].map { |i| i["actionKey"] }
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

  def inertia_props
    JSON.parse(response.body)["props"]
  end

  def sign_in(user, workspace)
    ApplicationController.any_instance.stubs(:current_user).returns(user)
    ApplicationController.any_instance.stubs(:current_workspace).returns(workspace)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
  end
end
