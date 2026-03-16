require "test_helper"
require "ostruct"

class SlackAuthenticationServiceTest < ActiveSupport::TestCase
  fixtures :incident_lifecycle_stages

  setup do
    @service = SlackAuthenticationService.new
    @auth_hash = mock_slack_auth_hash
  end

  test "process_oauth_callback creates workspace, user, and membership for first install" do
    stub_successful_slack_workflow
    result = @service.process_oauth_callback(@auth_hash)

    assert result[:workspace].present?
    assert result[:user].present?
    assert result[:membership].present?
    assert result[:first_install]

    # Verify workspace was created
    workspace = result[:workspace]
    assert_equal "slack", workspace.platform
    assert_equal @auth_hash.extra.team_info["id"], workspace.platform_id
    assert_equal "Test Workspace", workspace.name

    # Verify user was created
    user = result[:user]
    assert_equal "test@example.com", user.email
    assert_equal "Test User", user.name

    # Verify membership was created
    membership = result[:membership]
    assert_equal user.id, membership.user_id
    assert_equal workspace.id, membership.workspace_id
  end

  test "process_oauth_callback returns existing workspace for reinstall" do
    # Create existing workspace first
    team_id = "T#{SecureRandom.hex(8)}"
    existing_workspace = Workspace.create!(
    platform: "slack",
    platform_id: team_id,
    name: "Test Workspace",
    access_token: "existing-token",
    installed_at: Time.current,
    incidents_channel_id: "C12345678"
    )

    # Use auth_hash with matching team_id
    auth_hash = mock_slack_auth_hash(
    extra: { team_info: { "id" => team_id, "name" => "Test Workspace" } }
    )

    result = @service.process_oauth_callback(auth_hash)

    assert_equal existing_workspace.id, result[:workspace].id
    assert_not result[:first_install]
  end

  test "process_oauth_callback triggers workflow for first install" do
    stub_successful_slack_workflow
    SlackWorkspaceSetupWorkflow.expects(:start!).with do |workspace, context:|
      workspace.platform_id == @auth_hash.extra.team_info["id"] &&
        context[:installer_user_id] == "U12345678"
    end.returns(OpenStruct.new(id: "workflow-123", status: "running"))

    result = @service.process_oauth_callback(@auth_hash)

    assert result[:first_install]
  end

  test "process_oauth_callback does not trigger workflow for reinstall" do
    # Create existing workspace with channel already set up
    team_id = "T#{SecureRandom.hex(8)}"
    Workspace.create!(
    platform: "slack",
    platform_id: team_id,
    name: "Test Workspace",
    access_token: "existing-token",
    installed_at: Time.current,
    incidents_channel_id: "C12345678"
    )

    SlackWorkspaceSetupWorkflow.expects(:start!).never

    auth_hash = mock_slack_auth_hash(
    extra: { team_info: { "id" => team_id, "name" => "Test Workspace" } }
    )

    result = @service.process_oauth_callback(auth_hash)

    assert_not result[:first_install]
  end

  test "process_oauth_callback treats workspace without incidents_channel_id as first install" do
    # Create workspace without incidents channel
    team_id = "T#{SecureRandom.hex(8)}"
    existing_workspace = Workspace.create!(
    platform: "slack",
    platform_id: team_id,
    name: "Test Workspace",
    access_token: "existing-token",
    installed_at: Time.current,
    incidents_channel_id: nil
    )

    stub_successful_slack_workflow
    SlackWorkspaceSetupWorkflow.expects(:start!).once.returns(OpenStruct.new(id: "workflow-123", status: "running"))

    auth_hash = mock_slack_auth_hash(
      extra: { team_info: { "id" => team_id, "name" => "Test Workspace" } }
    )

    result = @service.process_oauth_callback(auth_hash)

    assert result[:first_install]
  end

  test "process_oauth_callback handles transaction rollback on error" do
    expected_platform_id = @auth_hash.extra.team_info["id"]

    Workspace.stubs(:find_or_create_from_slack!).raises(
      ActiveRecord::RecordInvalid.new(Workspace.new)
    )

    assert_no_difference [ "Workspace.count", "User.count", "WorkspaceMembership.count" ] do
      assert_raises(ActiveRecord::RecordInvalid) do
        @service.process_oauth_callback(@auth_hash)
      end
    end

    assert_nil User.find_by(email: "test@example.com")
    assert_nil Workspace.find_by(platform: "slack", platform_id: expected_platform_id)
  end

  test "process_oauth_callback updates existing user with new auth info" do
    # Create existing user
    existing_user = User.create!(
    email: "test@example.com",
    name: "Old Name"
    )

    stub_successful_slack_workflow
    result = @service.process_oauth_callback(@auth_hash)

    # User should be updated with new name
    existing_user.reload
    assert_equal "Test User", existing_user.name
    assert_equal existing_user.id, result[:user].id
  end

  test "process_oauth_callback logs workflow trigger event" do
    stub_successful_slack_workflow
    logged_events = []
    original_logger = Rails.logger

    begin
      Rails.logger = Logger.new(IO::NULL)
      Rails.logger.define_singleton_method(:info) do |message|
        logged_events << message if message.is_a?(Hash)
      end

      @service.process_oauth_callback(@auth_hash)

      workflow_log = logged_events.find { |e| e[:event] == "slack_authentication.workspace_setup_triggered" }
      assert workflow_log.present?, "Should log workflow trigger event"
      assert_equal "U12345678", workflow_log[:installer_user_id]
    ensure
      Rails.logger = original_logger
    end
  end
end
