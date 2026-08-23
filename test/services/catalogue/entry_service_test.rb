require "test_helper"

class Catalogue::EntryServiceTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :catalog_types, :catalog_attribute_definitions,
           :catalog_entries, :catalog_entry_relationships

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @service = Catalogue::EntryService.new(@workspace)
  end

  # Create

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

  # Update

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

  # Delete

  test "delete soft-deletes entry and destroys relationships" do
    auth_service = catalog_entries(:auth_service)
    assert auth_service.outgoing_relationships.exists?
    assert_nil auth_service.deleted_at

    @service.delete(auth_service)

    assert_not_nil auth_service.reload.deleted_at
    assert_not auth_service.outgoing_relationships.exists?
  end

  # Member attributes

  test "create resolves a member by the email they sign in with" do
    membership = workspace_memberships(:alice_workspace_one)
    team_type = catalog_types(:team_ws1)
    define_member_attribute(team_type, "team_lead", "Team Lead")

    entry = @service.create(
      type: team_type,
      name: "Email Lead Team",
      raw_attributes: { "team_lead" => "Alice@Example.com" }
    )

    assert_equal membership.id, entry.entry_attributes["team_lead"]
  end

  test "create resolves a member by platform user id" do
    membership = workspace_memberships(:alice_workspace_one)
    team_type = catalog_types(:team_ws1)
    define_member_attribute(team_type, "team_lead", "Team Lead")

    entry = @service.create(
      type: team_type,
      name: "Platform Id Team",
      raw_attributes: { "team_lead" => membership.platform_user_id }
    )

    assert_equal membership.id, entry.entry_attributes["team_lead"]
  end

  test "create keeps a member value that is already a workspace membership id" do
    membership = workspace_memberships(:alice_workspace_one)
    team_type = catalog_types(:team_ws1)
    define_member_attribute(team_type, "team_lead", "Team Lead")

    entry = @service.create(
      type: team_type,
      name: "Resubmitted Team",
      raw_attributes: { "team_lead" => membership.id }
    )

    assert_equal membership.id, entry.entry_attributes["team_lead"]
  end

  test "create resolves several members at once" do
    alice = workspace_memberships(:alice_workspace_one)
    bob = workspace_memberships(:bob_workspace_one)
    team_type = catalog_types(:team_ws1)
    define_member_attribute(team_type, "members", "Members", CatalogAttributeDefinition::TYPE_WORKSPACE_MEMBERS)

    entry = @service.create(
      type: team_type,
      name: "Multi Member Team",
      raw_attributes: { "members" => [ "alice@example.com", bob.platform_user_id ] }
    )

    assert_equal [ alice.id, bob.id ], entry.entry_attributes["members"]
  end

  test "create refuses a member nobody matches, and mints no membership for them" do
    team_type = catalog_types(:team_ws1)
    define_member_attribute(team_type, "team_lead", "Team Lead")

    WorkspaceMemberProvisioner.expects(:find_or_provision!).never

    error = nil
    assert_no_difference -> { WorkspaceMembership.count } do
      error = assert_raises(ActiveRecord::RecordInvalid) do
        @service.create(
          type: team_type,
          name: "Stranger Lead Team",
          raw_attributes: { "team_lead" => "nobody@example.com" }
        )
      end
    end

    assert_includes error.message, "Team Lead"
    assert_includes error.message, "nobody@example.com"
    assert_includes error.message, "email they sign in with"
    assert_nil CatalogEntry.find_by(slug: "stranger_lead_team")
  end

  test "create names only the members it could not match" do
    bob = workspace_memberships(:bob_workspace_one)
    team_type = catalog_types(:team_ws1)
    define_member_attribute(team_type, "members", "Members", CatalogAttributeDefinition::TYPE_WORKSPACE_MEMBERS)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      @service.create(
        type: team_type,
        name: "Partial Member Team",
        raw_attributes: { "members" => [ bob.platform_user_id, "nobody@example.com" ] }
      )
    end

    assert_includes error.message, "nobody@example.com"
    assert_not_includes error.message, bob.platform_user_id
    assert_nil CatalogEntry.find_by(slug: "partial_member_team")
  end

  test "update refuses an unmatched member instead of clearing the stored value" do
    membership = workspace_memberships(:alice_workspace_one)
    team_type = catalog_types(:team_ws1)
    define_member_attribute(team_type, "team_lead", "Team Lead")

    entry = @service.create(
      type: team_type,
      name: "Kept Lead Team",
      raw_attributes: { "team_lead" => membership.id }
    )

    assert_raises(ActiveRecord::RecordInvalid) do
      @service.update(entry, raw_attributes: { "team_lead" => "nobody@example.com" })
    end

    assert_equal membership.id, entry.reload.entry_attributes["team_lead"]
  end

  test "the dashboard provisions a member the workspace has never seen" do
    membership = workspace_memberships(:alice_workspace_one)
    team_type = catalog_types(:team_ws1)
    define_member_attribute(team_type, "team_lead", "Team Lead")

    WorkspaceMemberProvisioner.expects(:find_or_provision!)
      .with(workspace: @workspace, platform_user_id: "U99999999", adapter: anything)
      .returns(membership)

    entry = provisioning_service.create(
      type: team_type,
      name: "Freshly Picked Team",
      raw_attributes: { "team_lead" => "U99999999" }
    )

    assert_equal membership.id, entry.entry_attributes["team_lead"]
  end

  test "the dashboard reports a platform failure instead of storing nil" do
    team_type = catalog_types(:team_ws1)
    define_member_attribute(team_type, "team_lead", "Team Lead")

    WorkspaceMemberProvisioner.stubs(:find_or_provision!).returns(nil)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      provisioning_service.create(
        type: team_type,
        name: "Slack Down Team",
        raw_attributes: { "team_lead" => "U99999999" }
      )
    end

    assert_includes error.message, "Couldn't load the Slack profile"
    assert_nil CatalogEntry.find_by(slug: "slack_down_team")
  end

  private

  def provisioning_service
    @provisioning_service ||= Catalogue::EntryService.new(@workspace, may_provision_members: true)
  end

  def define_member_attribute(type, slug, name, attribute_type = CatalogAttributeDefinition::TYPE_WORKSPACE_MEMBER)
    type.catalog_attribute_definitions.create!(
      slug: slug,
      name: name,
      attribute_type: attribute_type,
      required: false,
      position: 20,
      config: {}
    )
  end
end
