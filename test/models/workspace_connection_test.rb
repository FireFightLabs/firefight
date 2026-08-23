require "test_helper"

class WorkspaceConnectionTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships

  setup do
    @workspace = Workspace.create!(
      platform: "slack", platform_id: "T#{SecureRandom.hex(8)}", name: "Connection Co",
      access_token: "xoxb-live", refresh_token: "xoxe-live", installed_at: Time.current, incidents_channel_id: "C1"
    )
  end

  test "a workspace starts connected and only a known reason can disconnect it" do
    assert_not @workspace.disconnected?
    assert_not @workspace.mark_disconnected!("invalid_auth"), "a possibly transient code does not flip the flag"
    assert_not @workspace.reload.disconnected?

    assert @workspace.mark_disconnected!(Workspace::Connection::DISCONNECTED_TOKEN_REVOKED)
    assert @workspace.disconnected?
    assert_equal "token_revoked", @workspace.disconnected_reason
  end

  test "the first report wins and a reinstall clears it" do
    @workspace.mark_disconnected!(Workspace::Connection::DISCONNECTED_TOKEN_REVOKED)
    first_at = @workspace.disconnected_at

    assert_not @workspace.mark_disconnected!(Workspace::Connection::DISCONNECTED_ACCOUNT_INACTIVE)
    assert_equal first_at, @workspace.reload.disconnected_at
    assert_equal "token_revoked", @workspace.disconnected_reason

    @workspace.mark_connected!
    assert_not @workspace.reload.disconnected?
    assert_nil @workspace.disconnected_reason
  end

  test "the Slack adapter records a revoked install and the refresh job stops retrying it" do
    Slack::AuthRevokedNotifier.notify(@workspace, error_code: "account_inactive")
    assert @workspace.reload.disconnected?

    @workspace.update!(token_expires_at: 1.hour.ago)
    assert_not_includes Slack::TokenManager.new.send(:expiring_workspaces, 3.hours).pluck(:id), @workspace.id
  end

  test "a refresh token Slack no longer accepts disconnects the workspace" do
    @workspace.update!(refresh_token: "xoxe-dead")
    Slack::TokenManager.any_instance.stubs(:call_slack_refresh_api).returns({ "ok" => false, "error" => "invalid_refresh_token" })

    assert_not Slack::TokenManager.new.refresh_workspace(@workspace)
    assert_equal "invalid_refresh_token", @workspace.reload.disconnected_reason
  end

  test "a reinstall through Slack OAuth reconnects the workspace" do
    @workspace.mark_disconnected!(Workspace::Connection::DISCONNECTED_TOKEN_REVOKED)
    auth_hash = OmniAuth::AuthHash.new(
      credentials: { token: "xoxb-new", refresh_token: "xoxe-new", expires_at: 1.day.from_now.to_i },
      extra: { team_info: { "id" => @workspace.platform_id, "name" => @workspace.name } }
    )

    Workspace.find_or_create_from_slack!(auth_hash)

    assert_not @workspace.reload.disconnected?
    assert_equal "xoxb-new", @workspace.access_token
  end
end
