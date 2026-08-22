require "test_helper"

class WorkspaceTest < ActiveSupport::TestCase
  fixtures :workspaces, :incident_lifecycle_stages

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
    assert_equal 5, workspace.incident_types.count
    assert_equal %w[data infrastructure production security third_party],
                 workspace.incident_types.pluck(:slug).sort
  end

  test "the first joiner owns the workspace and the next one does not" do
    team_id = "T#{SecureRandom.hex(8)}"
    first = Workspace.process_slack_installation(auth_hash_for(team_id))
    workspace = first[:workspace]

    second = Workspace.process_slack_installation(
      auth_hash_for(team_id, uid: "U_SECOND", info: { name: "Second", email: "second@example.com" })
    )

    assert_equal "owner", first[:membership].role
    assert_equal "member", second[:membership].role
    assert_equal workspace.id, second[:workspace].id
    assert_equal 1, workspace.reload.workspace_memberships.owners.count
  end

  # The check and the insert that answers it have to be one serialized step, or
  # two people finishing the install together both read an empty workspace and
  # both come out as owner.
  test "the first-member check runs under a workspace lock" do
    relation = mock
    relation.expects(:find).at_least_once.returns(nil)
    Workspace.expects(:lock).at_least_once.returns(relation)

    Workspace.process_slack_installation(mock_slack_auth_hash)
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
    expected_platform_id = auth_hash.extra.team_info["id"]

    User.stubs(:find_or_create_from_omniauth!).raises(
      ActiveRecord::RecordInvalid.new(User.new)
    )

    assert_no_difference [ "Workspace.count", "User.count", "WorkspaceMembership.count" ] do
      assert_raises(ActiveRecord::RecordInvalid) do
        Workspace.process_slack_installation(auth_hash)
      end
    end

    assert_nil Workspace.find_by(platform: "slack", platform_id: expected_platform_id)
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

  private

  def auth_hash_for(team_id, overrides = {})
    mock_slack_auth_hash(overrides.merge(extra: { team_info: { "id" => team_id, "name" => "Test Workspace" } }))
  end
end
