require "test_helper"

class ApprovalsControllerTest < ActionDispatch::IntegrationTest
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

    get gateway_approvals_url, headers: inertia_headers

    assert_response :success
    assert_equal [ @approval.id ], inertia_props["pendingApprovals"].map { |a| a["id"] }
    assert_equal [ resolved.id ], inertia_props["resolvedApprovals"].map { |a| a["id"] }
  end

  test "a command typed in Slack is shown on the approvals page as Slack shows it, and the record keeps it as sent" do
    bob = workspace_memberships(:bob_workspace_one)
    written = "<@#{bob.platform_user_id}> checkout is :fire: &amp; slow"
    params = { "command" => "/ff", "subcommand" => "investigate", "text" => "investigate #{written}" }
    command = Ability::Approval.create!(
      workspace: @workspace, principal: workspace_memberships(:alice_workspace_one), principal_label: "Alice",
      action_key: "investigations.create", params: params, source: AbilityGateway::SOURCE_SLACK,
      request_digest: Ability::Approval.digest("investigations.create", params, {}), required_role: WorkspaceMembership.roles[:admin]
    )

    get gateway_approvals_url, headers: inertia_headers

    shown = inertia_props["pendingApprovals"].find { |approval| approval["id"] == command.id }
    assert_equal "investigate @#{bob.display_name} checkout is 🔥 & slow", shown.dig("params", "text")
    assert_equal "/ff", shown.dig("params", "command")
    assert_equal "investigate #{written}", command.reload.params["text"]
  end

  test "the activity page renders the ledger" do
    AbilityGateway.authorize!(principal: api_keys(:full_access_key), action_key: "catalog.create",
                              workspace: @workspace) { :ok }

    get gateway_activity_url, headers: inertia_headers

    assert_response :success
    assert_equal [ "catalog.create" ], inertia_props["invocations"].map { |i| i["actionKey"] }
  end

  test "approve resolves the approval and redirects" do
    post approve_approval_url(@approval)

    assert_redirected_to gateway_approvals_path
    assert @approval.reload.approved?
    assert_equal "You approved Full Access Key's request. They can run it now.", flash[:notice]
  end

  test "a member without an approvals grant is refused by the gateway" do
    sign_in(users(:bob), @workspace)

    post deny_approval_url(@approval)

    assert_redirected_to dashboard_path
    assert_match "don't have permission to change approvals", flash[:alert]
    assert @approval.reload.pending?
  end

  test "deny without the required role redirects with the refusal" do
    sign_in(users(:bob), @workspace)
    @workspace.ability_grants.create!(
      principal: workspace_memberships(:bob_workspace_one),
      action: Ability::Action.system!(Ability::Action.system_key(Ability::Action::RESOURCE_APPROVALS, Ability::Action::ACTION_UPDATE))
    )

    post deny_approval_url(@approval)

    assert_redirected_to gateway_approvals_path
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
