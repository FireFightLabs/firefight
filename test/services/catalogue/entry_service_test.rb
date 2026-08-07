require "test_helper"

class Catalogue::EntryServiceTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :catalog_types, :catalog_attribute_definitions,
           :catalog_entries, :catalog_entry_relationships

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @service = Catalogue::EntryService.new(@workspace)
  end

  # ============================================================================
  # CREATE
  # ============================================================================

  test "create creates entry with validated attributes" do
    team_type = catalog_types(:team_ws1)

    entry = @service.create(
      type: team_type,
      name: "Backend Team",
      raw_attributes: { "description" => "Handles backend services" }
    )

    assert entry.persisted?
    assert_equal "Backend Team", entry.name
    assert_equal "backend_team", entry.slug
    assert_equal team_type, entry.catalog_type
    assert_equal @workspace, entry.workspace
    assert_equal "Handles backend services", entry.entry_attributes["description"]
  end

  test "create with reference attributes creates relationships" do
    service_type = catalog_types(:service_ws1)
    platform_team = catalog_entries(:platform_team)

    entry = @service.create(
      type: service_type,
      name: "Billing Service",
      raw_attributes: {
        "description" => "Handles billing",
        "tier" => "Standard",
        "owner_team" => platform_team.id
      }
    )

    assert entry.persisted?
    assert_equal "Handles billing", entry.entry_attributes["description"]
    rel = entry.outgoing_relationships.find_by!(relationship_key: "owner_team")
    assert_equal platform_team, rel.target_entry
  end

  test "create resolves a reference attribute given as a slug" do
    service_type = catalog_types(:service_ws1)
    platform_team = catalog_entries(:platform_team)

    entry = @service.create(
      type: service_type,
      name: "Search Service",
      raw_attributes: { "owner_team" => platform_team.slug }
    )

    rel = entry.outgoing_relationships.find_by!(relationship_key: "owner_team")
    assert_equal platform_team, rel.target_entry
  end

  test "create refuses a reference matching no entry and names the value it could not resolve" do
    service_type = catalog_types(:service_ws1)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      @service.create(
        type: service_type,
        name: "Orphan Service",
        raw_attributes: { "owner_team" => "no_such_team" }
      )
    end

    assert_includes error.message, "no_such_team"
  end

  test "create wraps in transaction -- sync_references failure rolls back entry creation" do
    service_type = catalog_types(:service_ws1)

    CatalogEntry.any_instance.stubs(:sync_references!).raises(ActiveRecord::RecordInvalid.new(CatalogEntry.new))

    assert_no_difference -> { CatalogEntry.count } do
      assert_raises(ActiveRecord::RecordInvalid) do
        @service.create(
          type: service_type,
          name: "Transactional Entry",
          raw_attributes: {
            "description" => "Should not persist",
            "owner_team" => "nonexistent-id"
          }
        )
      end
    end

    assert_nil CatalogEntry.find_by(slug: "transactional_entry")
  end

  # ============================================================================
  # UPDATE
  # ============================================================================

  test "update updates entry name and attributes" do
    auth_service = catalog_entries(:auth_service)

    result = @service.update(
      auth_service,
      name: "Auth Service V2",
      raw_attributes: { "description" => "Updated auth service", "tier" => "Standard" }
    )

    auth_service.reload
    assert_equal "Auth Service V2", auth_service.name
    assert_equal "Updated auth service", auth_service.entry_attributes["description"]
    assert_equal "Standard", auth_service.entry_attributes["tier"]
    assert_equal auth_service, result
  end

  test "update preserves slug when name changes" do
    auth_service = catalog_entries(:auth_service)
    original_slug = auth_service.slug

    @service.update(auth_service, name: "Renamed Auth", raw_attributes: { "description" => "Still auth" })

    assert_equal original_slug, auth_service.reload.slug
  end

  # ============================================================================
  # DELETE
  # ============================================================================

  test "delete soft-deletes entry and destroys relationships" do
    auth_service = catalog_entries(:auth_service)
    assert auth_service.outgoing_relationships.exists?
    assert_nil auth_service.deleted_at

    @service.delete(auth_service)

    assert_not_nil auth_service.reload.deleted_at
    assert_not auth_service.outgoing_relationships.exists?
  end

  # ============================================================================
  # MEMBER PROVISIONING
  # ============================================================================

  test "create provisions workspace_member attributes via WorkspaceMemberProvisioner" do
    membership = workspace_memberships(:alice_workspace_one)

    workspace = workspaces(:slack_workspace_one)
    team_type = catalog_types(:team_ws1)

    team_type.catalog_attribute_definitions.create!(
      slug: "team_lead",
      name: "Team Lead",
      attribute_type: CatalogAttributeDefinition::TYPE_WORKSPACE_MEMBER,
      required: false,
      position: 10,
      config: {}
    )

    WorkspaceMemberProvisioner.stubs(:find_or_provision!).returns(membership)

    entry = @service.create(
      type: team_type,
      name: "Provisioned Team",
      raw_attributes: { "team_lead" => "U12345678" }
    )

    assert entry.persisted?
    assert_equal membership.id, entry.entry_attributes["team_lead"]
  end

  test "create provisions workspace_members attributes as array" do
    alice_membership = workspace_memberships(:alice_workspace_one)
    bob_membership = workspace_memberships(:bob_workspace_one)

    team_type = catalog_types(:team_ws1)

    team_type.catalog_attribute_definitions.create!(
      slug: "members",
      name: "Members",
      attribute_type: CatalogAttributeDefinition::TYPE_WORKSPACE_MEMBERS,
      required: false,
      position: 11,
      config: {}
    )

    WorkspaceMemberProvisioner.stubs(:find_or_provision!)
      .with(workspace: @workspace, platform_user_id: "U12345678", adapter: anything)
      .returns(alice_membership)
    WorkspaceMemberProvisioner.stubs(:find_or_provision!)
      .with(workspace: @workspace, platform_user_id: "U87654321", adapter: anything)
      .returns(bob_membership)

    entry = @service.create(
      type: team_type,
      name: "Multi Member Team",
      raw_attributes: { "members" => [ "U12345678", "U87654321" ] }
    )

    assert entry.persisted?
    assert_equal [ alice_membership.id, bob_membership.id ], entry.entry_attributes["members"]
  end
end
