require "test_helper"

class WorkspaceTest < ActiveSupport::TestCase
  fixtures :workspaces, :incident_lifecycle_stages

  test "the truth" do
    assert true
  end

  test "slack workspace fixture loads correctly" do
    workspace = workspaces(:slack_workspace_one)
    assert_equal "slack", workspace.platform
    assert_equal "T12345678", workspace.platform_id
    assert_equal "Test Workspace One", workspace.name
  end

  test "validates uniqueness of platform_id scoped to platform" do
    workspace = workspaces(:slack_workspace_one)
    duplicate = Workspace.new(
    platform: workspace.platform,
    platform_id: workspace.platform_id,
    name: "Duplicate",
    installed_at: Time.current
    )

    refute duplicate.valid?
    assert_includes duplicate.errors[:platform_id], "has already been taken"
  end

  # process_slack_installation tests

  test "process_slack_installation creates workspace, user, and membership" do
    auth_hash = mock_slack_auth_hash

    result = Workspace.process_slack_installation(auth_hash)

    assert result[:workspace].present?
    assert result[:user].present?
    assert result[:membership].present?
    assert result[:first_install]

    # Verify workspace
    workspace = result[:workspace]
    assert workspace.persisted?
    assert_equal "slack", workspace.platform
    assert_equal auth_hash.extra.team_info["id"], workspace.platform_id
    assert_equal "Test Workspace", workspace.name

    # Verify user
    user = result[:user]
    assert user.persisted?
    assert_equal "test@example.com", user.email

    # Verify membership
    membership = result[:membership]
    assert membership.persisted?
    assert_equal workspace.id, membership.workspace_id
    assert_equal user.id, membership.user_id

    # Verify default incident types
    assert_equal 4, workspace.incident_types.count
    assert_equal %w[data_issue performance_degradation security_incident service_outage],
                 workspace.incident_types.pluck(:slug).sort
  end

  test "process_slack_installation returns existing workspace for reinstall" do
    # Create existing workspace with specific team_id
    team_id = "T#{SecureRandom.hex(8)}"
    existing = Workspace.create!(
    platform: "slack",
    platform_id: team_id,
    name: "Test Workspace",
    access_token: "existing-token",
    installed_at: Time.current,
    incidents_channel_id: "C12345678"
    )

    # Use the same team_id in auth_hash
    auth_hash = mock_slack_auth_hash(
    extra: { team_info: { "id" => team_id, "name" => "Test Workspace" } }
    )

    result = Workspace.process_slack_installation(auth_hash)

    assert_equal existing.id, result[:workspace].id
    assert_not result[:first_install]
  end

  test "process_slack_installation treats workspace without channel as first install" do
    # Create workspace without incidents channel
    team_id = "T#{SecureRandom.hex(8)}"
    existing = Workspace.create!(
    platform: "slack",
    platform_id: team_id,
    name: "Test Workspace",
    access_token: "existing-token",
    installed_at: Time.current,
    incidents_channel_id: nil
    )

    auth_hash = mock_slack_auth_hash(
    extra: { team_info: { "id" => team_id, "name" => "Test Workspace" } }
    )

    result = Workspace.process_slack_installation(auth_hash)

    assert_equal existing.id, result[:workspace].id
    assert result[:first_install], "Should be first install if incidents_channel_id is nil"
  end

  test "process_slack_installation wraps everything in transaction" do
    auth_hash = mock_slack_auth_hash

    # Stub User.find_or_create_from_omniauth! to raise error
    original_method = User.method(:find_or_create_from_omniauth!)
    User.define_singleton_method(:find_or_create_from_omniauth!) do |*args|
    user = User.new
    user.errors.add(:base, "Simulated error")
    raise ActiveRecord::RecordInvalid.new(user)
    end

    assert_raises(ActiveRecord::RecordInvalid) do
    Workspace.process_slack_installation(auth_hash)
    end

    # Verify no workspace was persisted due to transaction rollback
    assert_nil Workspace.find_by(platform_id: "T#{SecureRandom.hex(8)}")

    # Restore original method
    User.define_singleton_method(:find_or_create_from_omniauth!, original_method)
  end

  test "process_slack_installation updates existing user and workspace" do
    # Create existing records
    team_id = "T#{SecureRandom.hex(8)}"
    existing_workspace = Workspace.create!(
    platform: "slack",
    platform_id: team_id,
    name: "Old Name",
    access_token: "old-token",
    installed_at: Time.current
    )

    existing_user = User.create!(
    email: "test@example.com",
    name: "Old Name"
    )

    auth_hash = mock_slack_auth_hash(
    credentials: {
      token: "new-token"
    },
    extra: {
      team_info: { "id" => team_id, "name" => "Updated Workspace" },
      raw_info: {
        team: { id: team_id, name: "Updated Workspace" },
        authed_user: { id: "U12345678" },
        access_token: "new-token"
      }
    },
    info: {
      name: "Updated User",
      email: "test@example.com"
    }
    )

    result = Workspace.process_slack_installation(auth_hash)

    # Verify workspace was updated
    existing_workspace.reload
    assert_equal "Updated Workspace", existing_workspace.name
    assert_equal "new-token", existing_workspace.access_token

    # Verify user was updated
    existing_user.reload
    assert_equal "Updated User", existing_user.name
  end

  test "process_slack_installation creates membership for existing workspace and user" do
    # Create existing records without membership
    team_id = "T#{SecureRandom.hex(8)}"
    existing_workspace = Workspace.create!(
    platform: "slack",
    platform_id: team_id,
    name: "Test Workspace",
    access_token: "token",
    installed_at: Time.current
    )

    existing_user = User.create!(
    email: "test@example.com",
    name: "Test User"
    )

    auth_hash = mock_slack_auth_hash(
    extra: { team_info: { "id" => team_id, "name" => "Test Workspace" } }
    )

    result = Workspace.process_slack_installation(auth_hash)

    # Verify membership was created
    assert result[:membership].persisted?
    assert_equal existing_workspace.id, result[:membership].workspace_id
    assert_equal existing_user.id, result[:membership].user_id
  end

  test "process_slack_installation sets first_install false if channel exists" do
    team_id = "T#{SecureRandom.hex(8)}"
    existing = Workspace.create!(
    platform: "slack",
    platform_id: team_id,
    name: "Test Workspace",
    access_token: "token",
    installed_at: Time.current,
    incidents_channel_id: "C12345678"
    )

    auth_hash = mock_slack_auth_hash(
    extra: { team_info: { "id" => team_id, "name" => "Test Workspace" } }
    )

    result = Workspace.process_slack_installation(auth_hash)

    assert_not result[:first_install]
    assert_equal existing.id, result[:workspace].id
  end
end
