require "test_helper"
require "ostruct"

class SlackAuthenticationServiceTest < ActiveSupport::TestCase
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

  # handle_openid_signin, signed_in + install_needed. No invite gate here.
  # Installs are gated in handle_install.

  test "handle_openid_signin returns install_needed when workspace doesn't exist" do
    auth_hash = mock_slack_openid_auth_hash(
      info: { email: "newuser@example.com", team_id: "T_DOES_NOT_EXIST", team_name: "Brand New Co" }
    )

    outcome = @service.handle_openid_signin(auth_hash)

    assert outcome.install_needed?
    assert_equal "T_DOES_NOT_EXIST", outcome.team_id
    assert_equal "Brand New Co", outcome.team_name
    assert outcome.user.persisted?
    assert_equal "newuser@example.com", outcome.user.email
  end

  test "handle_openid_signin signs in existing member" do
    workspace = workspaces(:slack_workspace_one)
    alice = users(:alice)
    auth_hash = mock_slack_openid_auth_hash(
      uid: "U12345678",
      info: { email: alice.email, team_id: workspace.platform_id, team_name: workspace.name }
    )

    outcome = @service.handle_openid_signin(auth_hash)

    assert outcome.signed_in?
    assert_equal workspace_memberships(:alice_workspace_one).id, outcome.membership.id
    assert_nil outcome.message, "a returning sign-in announces nothing"
  end

  test "handle_openid_signin auto-provisions when workspace exists and user has no membership" do
    workspace = workspaces(:slack_workspace_one)
    auth_hash = mock_slack_openid_auth_hash(
      uid: "U_NEW_MEMBER",
      info: { email: "newbie@example.com", team_id: workspace.platform_id, team_name: workspace.name }
    )

    assert_difference -> { workspace.workspace_memberships.count }, 1 do
      outcome = @service.handle_openid_signin(auth_hash)

      assert outcome.signed_in?
      assert_equal "newbie@example.com", outcome.membership.user.email
      assert_equal "U_NEW_MEMBER", outcome.membership.platform_user_id
      assert_equal "member", outcome.membership.role
      assert_equal "Welcome to #{workspace.name}.", outcome.message
    end
  end

  # handle_install, wraps install path in AuthOutcome

  test "handle_install returns signed_in outcome and triggers setup on first install" do
    stub_successful_slack_workflow
    SlackWorkspaceSetupWorkflow.expects(:start!).once.returns(OpenStruct.new(id: "wf-1", status: "running"))

    outcome = @service.handle_install(
      @auth_hash,
      user: users(:charlie),
      invite_code: invite_codes(:active_public_beta_code)
    )

    assert outcome.signed_in?
    assert outcome.membership.persisted?
    assert_equal "Setting up your Firefight workspace...", outcome.message
  end

  test "handle_install rejects install when pending_team_id does not match auth_hash team" do
    invite_code = invite_codes(:active_public_beta_code)

    assert_no_difference -> { Workspace.count } do
      outcome = @service.handle_install(
        @auth_hash,
        user: users(:charlie),
        invite_code: invite_code,
        pending_team_id: "T_DIFFERENT_FROM_AUTH_HASH"
      )

      assert outcome.invite_required?
      assert_equal SlackAuthenticationService::WORKSPACE_MISMATCH_MESSAGE, outcome.message
    end

    assert_not invite_code.reload.redeemed?
  end

  test "handle_install rejects first install when installer (user) is missing" do
    invite_code = invite_codes(:active_public_beta_code)

    assert_no_difference -> { Workspace.count } do
      outcome = @service.handle_install(@auth_hash, invite_code: invite_code)

      assert outcome.invite_required?
      assert_equal SlackAuthenticationService::INVITE_REQUIRED_MESSAGE, outcome.message
    end

    assert_not invite_code.reload.redeemed?
  end

  test "handle_install returns invite_required when invite code was already redeemed concurrently" do
    invite_code = invite_codes(:active_public_beta_code)
    invite_code.update!(redeemed_at: Time.current)

    outcome = @service.handle_install(@auth_hash, user: users(:charlie), invite_code: invite_code)

    assert outcome.invite_required?
    assert_equal SlackAuthenticationService::INVITE_REQUIRED_MESSAGE, outcome.message
  end

  test "handle_install returns invite_required when installing a new workspace without invite" do
    outcome = @service.handle_install(@auth_hash)

    assert outcome.invite_required?
    assert_equal SlackAuthenticationService::INVITE_REQUIRED_MESSAGE, outcome.message
  end

  test "handle_install returns signed_in outcome without triggering setup on reinstall" do
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

    outcome = @service.handle_install(auth_hash)

    assert outcome.signed_in?
    assert_equal "Signed in.", outcome.message
  end
end
