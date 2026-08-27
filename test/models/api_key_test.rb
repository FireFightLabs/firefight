require "test_helper"

class ApiKeyTest < ActiveSupport::TestCase
  # Token generation

  test "generate_token produces token with ff_ prefix" do
    token = ApiKey.generate_token
    assert token.start_with?("ff_")
    assert_equal 39, token.length  # "ff_" + 36 chars
  end

  test "create_with_token! returns api_key and raw token" do
    api_key, raw_token = ApiKey.create_with_token!(
      workspace: workspaces(:slack_workspace_one),
      created_by: workspace_memberships(:alice_workspace_one),
      name: "Test Key"
    )

    assert api_key.persisted?
    assert raw_token.start_with?("ff_")
    assert_equal raw_token.first(12), api_key.token_prefix
    assert_equal Digest::SHA256.hexdigest(raw_token), api_key.token_digest
  end

  # Principals

  test "personal token resolves to the human principal; service key to itself" do
    membership = workspace_memberships(:alice_workspace_one)
    personal, _ = ApiKey.create_with_token!(
      workspace: workspaces(:slack_workspace_one), created_by: membership,
      on_behalf_of: membership, name: "Alice's Claude Code"
    )
    service, _ = ApiKey.create_with_token!(
      workspace: workspaces(:slack_workspace_one), created_by: membership, name: "CI"
    )

    assert personal.personal?
    assert_equal membership, personal.principal
    assert service.service?
    assert_equal service, service.principal
  end

  test "the matrix refuses an admin-only resource" do
    key = api_keys(:read_only_key)

    assert_raises(ArgumentError) do
      key.replace_permissions!(Ability::Action::RESOURCE_API_KEYS => [ Ability::Action::ACTION_CREATE ])
    end
  end

  test "member personal tokens read everything, participate in incidents, and configure nothing" do
    membership = workspace_memberships(:bob_workspace_one)
    key, _ = ApiKey.create_with_token!(
      workspace: workspaces(:slack_workspace_one), created_by: membership,
      on_behalf_of: membership, name: "Personal"
    )

    Ability::Action::GRANTABLE_RESOURCES.each do |resource|
      assert key.has_permission?(resource, Ability::Action::ACTION_READ)
      assert_not key.has_permission?(resource, Ability::Action::ACTION_DELETE)
    end
    Ability::Action::ADMIN_ONLY_RESOURCES.each do |resource|
      assert_not key.has_permission?(resource, Ability::Action::ACTION_READ)
    end

    assert key.has_permission?(Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_CREATE)
    assert key.has_permission?(Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE)

    (Ability::Action::RESOURCES - [ Ability::Action::RESOURCE_INCIDENTS ]).each do |resource|
      assert_not key.has_permission?(resource, Ability::Action::ACTION_CREATE)
      assert_not key.has_permission?(resource, Ability::Action::ACTION_UPDATE)
    end
  end

  test "admin personal tokens carry the admin's write authority" do
    membership = workspace_memberships(:alice_workspace_one)
    key, _ = ApiKey.create_with_token!(
      workspace: workspaces(:slack_workspace_one), created_by: membership,
      on_behalf_of: membership, name: "Admin personal"
    )

    assert key.has_permission?(Ability::Action::RESOURCE_CATALOG, Ability::Action::ACTION_CREATE)
    assert key.has_permission?(Ability::Action::RESOURCE_CATALOG, Ability::Action::ACTION_DELETE)
  end

  test "on_behalf_of must belong to the same workspace" do
    other_member = workspace_memberships(:alice_workspace_two)
    key = ApiKey.new(
      workspace: workspaces(:slack_workspace_one),
      created_by: workspace_memberships(:alice_workspace_one),
      on_behalf_of: other_member, name: "X",
      token_digest: "d", token_prefix: "p"
    )

    assert_not key.valid?
    assert key.errors[:on_behalf_of].any?
  end

  test "destroying a membership revokes its personal tokens" do
    user = User.create!(name: "Temp Member", email: "temp-member@example.com")
    membership = WorkspaceMembership.create!(
      user: user, workspace: workspaces(:slack_workspace_one),
      platform_user_id: "U_TEMP_MEMBER", role: :member, joined_at: Time.current
    )
    key, raw = ApiKey.create_with_token!(
      workspace: workspaces(:slack_workspace_one), created_by: membership,
      on_behalf_of: membership, name: "Bob's token"
    )
    assert_equal key, ApiKey.authenticate(raw)

    membership.destroy!

    assert_nil ApiKey.find_by(id: key.id)
    assert_nil ApiKey.authenticate(raw)
  end

  # Authentication

  test "authenticate returns api_key for valid token" do
    api_key = ApiKey.authenticate("ff_test_full_access_token_123456")
    assert_not_nil api_key
    assert_equal api_keys(:full_access_key), api_key
  end

  test "authenticate returns nil for invalid token" do
    assert_nil ApiKey.authenticate("ff_invalid_token")
  end

  test "authenticate returns nil for blank token" do
    assert_nil ApiKey.authenticate("")
    assert_nil ApiKey.authenticate(nil)
  end

  test "authenticate returns nil for inactive key" do
    assert_nil ApiKey.authenticate("ff_test_inactive_token_123456789")
  end

  test "authenticate returns nil for expired key" do
    assert_nil ApiKey.authenticate("ff_test_expired_token_1234567890")
  end

  test "authenticate returns nil for soft-deleted key" do
    assert_nil ApiKey.authenticate("ff_test_deleted_token_1234567890")
  end

  # Permissions

  test "has_permission? returns true for granted permission" do
    key = api_keys(:full_access_key)
    assert key.has_permission?("incidents", "read")
    assert key.has_permission?("incidents", "create")
    assert key.has_permission?("incidents", "update")
    assert key.has_permission?("severities", "read")
  end

  test "has_permission? returns false for denied permission" do
    key = api_keys(:read_only_key)
    assert_not key.has_permission?("incidents", "create")
    assert_not key.has_permission?("incidents", "update")
    assert_not key.has_permission?("incidents", "delete")
  end

  test "has_permission? returns false for unknown resource" do
    key = api_keys(:full_access_key)
    assert_not key.has_permission?("unknown", "read")
  end

  test "replace_permissions! writes the matrix straight to grants" do
    key, _ = create_service_key(
      workspace: workspaces(:slack_workspace_one),
      created_by: workspace_memberships(:alice_workspace_one),
      name: "Synced Key",
      permissions: { Ability::Action::RESOURCE_ALERTS => [ Ability::Action::ACTION_READ, Ability::Action::ACTION_CREATE ] }
    )

    granted = Ability::Grant.where(principal: key).joins(:action).pluck("ability_actions.key")
    assert_equal [ "alerts.create", "alerts.read" ], granted.sort
    assert key.has_permission?(Ability::Action::RESOURCE_ALERTS, Ability::Action::ACTION_CREATE)
    assert_not key.has_permission?(Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_READ)

    key.replace_permissions!({ Ability::Action::RESOURCE_ALERTS => [ Ability::Action::ACTION_READ ] })
    granted = Ability::Grant.where(principal: key).joins(:action).pluck("ability_actions.key")
    assert_equal [ "alerts.read" ], granted
    assert_not key.has_permission?(Ability::Action::RESOURCE_ALERTS, Ability::Action::ACTION_CREATE)
  end

  test "granted_permissions reads the matrix back out of the grants" do
    key = api_keys(:read_only_key)

    assert_equal({ "incidents" => [ "read" ], "severities" => [ "read" ],
                   "statuses" => [ "read" ], "incident_types" => [ "read" ] }.transform_values(&:sort),
                 key.granted_permissions.transform_values(&:sort))
  end

  # The bug this replaced, a grant made on the Permissions screen used to be
  # reconciled away the next time the key was saved for any reason.
  test "a grant made outside the matrix survives an unrelated save and shows up ticked" do
    key = api_keys(:read_only_key)
    Ability::Grant.create!(workspace: key.workspace, principal: key,
                           action: Ability::Action.system!("runbooks.create"))

    key.update!(name: "renamed, permissions untouched")

    assert_includes Ability::Grant.where(principal: key).joins(:action).pluck("ability_actions.key"),
                    "runbooks.create"
    assert_includes key.reload.granted_permissions["runbooks"], "create"
  end

  test "replace_permissions! refuses a resource outside the matrix" do
    key = api_keys(:read_only_key)

    assert_raises(ArgumentError) { key.replace_permissions!({ "nonsense" => [ "read" ] }) }
  end

  test "personal tokens hold no grants" do
    membership = workspace_memberships(:bob_workspace_one)
    key, _ = ApiKey.create_with_token!(
      workspace: workspaces(:slack_workspace_one), created_by: membership,
      on_behalf_of: membership, name: "Personal"
    )

    assert_empty Ability::Grant.where(principal: key)
    assert key.has_permission?(Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_READ)
    assert_not key.has_permission?(Ability::Action::RESOURCE_SEVERITIES, Ability::Action::ACTION_CREATE)
  end


  # Soft delete

  test "soft_delete! sets deleted_at" do
    key = api_keys(:full_access_key)
    key.soft_delete!
    assert key.deleted?
    assert_not_nil key.deleted_at
  end

  test "soft-deleted key excluded from active scope" do
    key = api_keys(:deleted_key)
    assert_not_includes ApiKey.active, key
  end

  # Expiration

  test "expired? returns true for expired key" do
    assert api_keys(:expired_key).expired?
  end

  test "expired? returns false for non-expired key" do
    assert_not api_keys(:full_access_key).expired?
  end

  test "expired? returns false when expires_at is nil" do
    assert_not api_keys(:read_only_key).expired?
  end

  # Last used tracking

  test "touch_last_used! updates last_used_at" do
    key = api_keys(:full_access_key)
    assert_nil key.last_used_at

    key.touch_last_used!
    assert_not_nil key.reload.last_used_at
  end

  test "touch_last_used! is debounced within 1 minute" do
    key = api_keys(:full_access_key)
    key.update_column(:last_used_at, 30.seconds.ago)
    original = key.last_used_at

    key.touch_last_used!
    assert_equal original.to_i, key.reload.last_used_at.to_i
  end
end
