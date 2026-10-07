require "test_helper"

class Workspace::ChatConnectionTest < ActiveSupport::TestCase
  include OmniauthTestHelper

  setup do
    @unconnected = Workspace.sign_up!(name: "Before Slack", user: users(:alice)).workspace
  end

  test "a workspace can exist with no chat platform, and says incidents wait for one" do
    assert @unconnected.valid?
    assert_not @unconnected.chat_connected?
    assert_equal "Connect Slack first to run incidents.", @unconnected.incidents_blocked_reason
  end

  test "a connected workspace can run incidents" do
    assert workspaces(:slack_workspace_one).chat_connected?
    assert_nil workspaces(:slack_workspace_one).incidents_blocked_reason
  end

  test "a platform needs its id and install time, and an id needs its platform" do
    @unconnected.platform = Platforms::SLACK
    assert_not @unconnected.valid?
    assert @unconnected.errors[:platform_id].any?

    @unconnected.platform = nil
    @unconnected.platform_id = "T_ORPHAN"
    assert_not @unconnected.valid?
    assert @unconnected.errors[:platform].any?
  end

  test "two workspaces without a platform do not collide on the platform id" do
    other = Workspace.sign_up!(name: "Also Before Slack", user: users(:bob)).workspace

    assert other.valid?
    assert @unconnected.valid?
  end

  test "connecting fills the platform columns and keeps the chosen name" do
    auth = mock_slack_auth_hash(extra: { team_info: { "id" => "T_CONNECT_ME", "name" => "Slack Name" } })

    @unconnected.connect_slack!(auth)

    @unconnected.reload
    assert @unconnected.chat_connected?
    assert_equal "T_CONNECT_ME", @unconnected.platform_id
    assert_equal "Before Slack", @unconnected.name
    assert_equal "xoxb-test-token-12345", @unconnected.access_token
    assert @unconnected.installed_at
  end

  test "a connected workspace cannot be connected again" do
    auth = mock_slack_auth_hash

    assert_raises(Workspace::ChatConnection::AlreadyConnected) { workspaces(:slack_workspace_one).connect_slack!(auth) }
  end

  test "incident creation refuses with the reason" do
    error = assert_raises(Incident::CreationBlocked) do
      IncidentLifecycleService.new(@unconnected).create(
        name: "Checkout failing",
        incident_status: @unconnected.incident_statuses.default_status,
        incident_severity: @unconnected.incident_severities.first,
        declared_by: @unconnected.workspace_memberships.first,
        source: Incident::SOURCE_DASHBOARD
      )
    end

    assert_equal "Connect Slack first to run incidents.", error.message
    assert_equal 0, @unconnected.incidents.count
  end
end
