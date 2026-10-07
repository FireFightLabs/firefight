require "test_helper"
require Rails.root.join("db/migrate/20261007230300_backfill_slack_user_identities")

class BackfillSlackUserIdentitiesTest < ActiveSupport::TestCase
  test "every Slack member gets a Slack sign-in method by team and user id, and running again adds nothing" do
    membership = workspace_memberships(:alice_workspace_one)

    2.times { ActiveRecord::Migration.suppress_messages { BackfillSlackUserIdentities.new.migrate(:up) } }

    identity = UserIdentity.find_by!(provider: UserIdentity::SLACK, uid: "#{membership.workspace.platform_id}/#{membership.platform_user_id}")
    assert_equal membership.user, identity.user
    assert_equal WorkspaceMembership.joins(:workspace).where(workspaces: { platform: "slack" })
      .distinct.count("workspaces.platform_id || '/' || workspace_memberships.platform_user_id"), UserIdentity.where(provider: UserIdentity::SLACK).count
  end

  test "a Slack sign-in after the backfill reaches the same person by id even with a new email" do
    membership = workspace_memberships(:alice_workspace_one)
    ActiveRecord::Migration.suppress_messages { BackfillSlackUserIdentities.new.migrate(:up) }
    auth_hash = mock_slack_openid_auth_hash(
      uid: membership.platform_user_id,
      info: { email: "alice.renamed@example.com", team_id: membership.workspace.platform_id, team_name: membership.workspace.name }
    )

    outcome = SlackAuthenticationService.new.handle_openid_signin(auth_hash)

    assert_equal membership, outcome.membership
    assert_nil User.find_by(email: "alice.renamed@example.com")
  end
end
