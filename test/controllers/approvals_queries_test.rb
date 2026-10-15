require "test_helper"

# What the approvals page costs the database for someone who is not an admin. Whether they may decide each request is
# asked of the request already read, so more requests must not mean more queries.
class ApprovalsQueriesTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    sign_in(users(:bob), @workspace)
  end

  test "the page costs the same for many pending requests as for a few" do
    held(2)
    get gateway_approvals_url, headers: inertia_headers
    few = queries_sent { get gateway_approvals_url, headers: inertia_headers }
    held(12)
    many = queries_sent { get gateway_approvals_url, headers: inertia_headers }

    assert_response :success
    assert_same_queries few, many
  end

  private

  def held(count)
    count.times do
      Ability::Approval.create!(workspace: @workspace, principal: api_keys(:full_access_key), principal_label: api_keys(:full_access_key).principal_label,
                                action_key: "catalog.delete", request_digest: Ability::Approval.digest("catalog.delete", { "n" => SecureRandom.hex(3) }, {}),
                                required_role: WorkspaceMembership.roles[:admin])
    end
  end
end
