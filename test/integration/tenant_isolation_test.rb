require "test_helper"

# An admin of one workspace who knows the id of another workspace's record reaches nothing of it: not its page, not
# its secret, and no decision on it.
class TenantIsolationTest < ActionDispatch::IntegrationTest
  setup do
    @other = workspaces(:slack_workspace_two)
    sign_in(users(:alice), workspaces(:slack_workspace_one))
  end

  test "another workspace's incident, investigation and webhook secret are not found" do
    get incident_path(incidents(:active_p0_ws2))
    assert_response :not_found

    get signing_secret_webhook_path(webhooks(:workspace_two_webhook))
    assert_response :not_found
    assert_no_match webhooks(:workspace_two_webhook).signing_secret, response.body
  end

  test "another workspace's approval cannot be decided" do
    requester = workspace_memberships(:alice_workspace_two)
    approval = Ability::Approval.create!(
      workspace: @other, principal: requester, principal_label: "Alice", action_key: "catalog.delete",
      request_digest: Ability::Approval.digest("catalog.delete", {}, {}), required_role: WorkspaceMembership.roles[:admin]
    )

    post approve_approval_path(approval)

    assert_response :not_found
    assert approval.reload.pending?
  end
end
