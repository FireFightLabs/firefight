require "test_helper"

class CatalogEntryTest < ActiveSupport::TestCase
  test "in_system_type resolves active entries through their type's system key" do
    workspace = workspaces(:slack_workspace_one)

    entry = workspace.catalog_entries.in_system_type(CatalogType::SYSTEM_KEY_SERVICE).find_by(slug: "auth_service")
    assert_equal catalog_entries(:auth_service), entry

    catalog_entries(:auth_service).update!(deleted_at: Time.current)
    assert_nil workspace.catalog_entries.in_system_type(CatalogType::SYSTEM_KEY_SERVICE).find_by(slug: "auth_service")
  end

  test "active_outgoing_relationships drops hops to deleted targets" do
    service = catalog_entries(:auth_service)
    assert_equal [ catalog_entries(:platform_team) ],
                 service.active_outgoing_relationships.map(&:target_entry)

    catalog_entries(:platform_team).update!(deleted_at: Time.current)
    assert_empty service.reload.active_outgoing_relationships
  end

  test "active_outgoing_relationships reads a preloaded association without a query" do
    service = CatalogEntry.includes(outgoing_relationships: { target_entry: :catalog_type })
      .find(catalog_entries(:auth_service).id)

    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      service.active_outgoing_relationships
    end

    assert_equal 0, queries
  end

  # Basic validations

  test "requires name" do
    entry = CatalogEntry.new(
      workspace: workspaces(:slack_workspace_one),
      catalog_type: catalog_types(:team_ws1),
      slug: "test_entry"
    )
    assert_not entry.valid?
    assert_includes entry.errors[:name], "can't be blank"
  end

  test "requires slug" do
    entry = CatalogEntry.new(
      workspace: workspaces(:slack_workspace_one),
      catalog_type: catalog_types(:team_ws1),
      name: "Test Entry"
    )
    assert_not entry.valid?
    assert_includes entry.errors[:slug], "can't be blank"
  end

  test "slug must be unique within type" do
    existing = catalog_entries(:platform_team)
    duplicate = CatalogEntry.new(
      workspace: existing.workspace,
      catalog_type: existing.catalog_type,
      name: "Another Team",
      slug: existing.slug
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:slug], "has already been taken"
  end

  test "workspace must match type workspace" do
    entry = CatalogEntry.new(
      workspace: workspaces(:slack_workspace_two),
      catalog_type: catalog_types(:team_ws1),
      name: "Mismatched Entry",
      slug: "mismatched"
    )
    assert_not entry.valid?
    assert_includes entry.errors[:workspace], "must match the catalog type's workspace"
  end

  # Scopes

  test "active scope excludes deleted entries" do
    deleted = catalog_entries(:deleted_entry)
    active_entries = CatalogEntry.active

    assert_not_includes active_entries, deleted
    assert_includes active_entries, catalog_entries(:platform_team)
  end

  test "ordered scope orders by name" do
    workspace = workspaces(:slack_workspace_one)
    entries = workspace.catalog_entries.active.ordered
    names = entries.map(&:name)
    assert_equal names.sort, names
  end

  # Entry attributes

  test "entry_attributes returns the jsonb attributes hash" do
    auth = catalog_entries(:auth_service)
    attrs = auth.entry_attributes

    assert_equal "Handles authentication", attrs["description"]
    assert_equal "Critical", attrs["tier"]
  end

  test "entry_attributes returns empty hash when nil" do
    entry = CatalogEntry.new
    assert_equal({}, entry.entry_attributes)
  end

  # Assign validated attributes, splitting

  test "assign_validated_attributes! splits scalar vs reference attrs" do
    auth = catalog_entries(:auth_service)
    team = catalog_entries(:platform_team)

    scalar, reference = auth.assign_validated_attributes!({
      "description" => "Updated auth",
      "tier" => "Standard",
      "owner_team" => team.id
    })

    assert_equal({ "description" => "Updated auth", "tier" => "Standard" }, scalar)
    assert_equal({ "owner_team" => team.id }, reference)
  end

  test "assign_validated_attributes! rejects unknown attribute keys" do
    auth = catalog_entries(:auth_service)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      auth.assign_validated_attributes!({ "nonexistent_attr" => "value" })
    end
    assert_match(/Unknown attribute key/, error.message)
  end

  # Assign validated attributes, type validations

  test "assign_validated_attributes! validates select values in options" do
    auth = catalog_entries(:auth_service)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      auth.assign_validated_attributes!({ "tier" => "InvalidTier" })
    end
    assert_match(/Tier must be one of/, error.message)
  end

  test "assign_validated_attributes! validates boolean is true or false" do
    prod = catalog_entries(:production_env)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      prod.assign_validated_attributes!({ "is_production" => "yes" })
    end
    assert_match(/Is Production must be true or false/, error.message)
  end

  test "assign_validated_attributes! accepts valid boolean values" do
    prod = catalog_entries(:production_env)

    scalar, _ref = prod.assign_validated_attributes!({ "is_production" => true })
    assert_equal true, scalar["is_production"]

    scalar, _ref = prod.assign_validated_attributes!({ "is_production" => false })
    assert_equal false, scalar["is_production"]
  end

  test "assign_validated_attributes! validates list is array of strings" do
    workspace = workspaces(:slack_workspace_one)
    list_type = CatalogType.create!(
      workspace: workspace, name: "List Test", slug: "list_test",
      kind: CatalogType::KIND_CUSTOM, position: 99
    )
    list_type.catalog_attribute_definitions.create!(
      slug: "tags", name: "Tags",
      attribute_type: CatalogAttributeDefinition::TYPE_LIST,
      required: false, position: 1, config: {}
    )
    entry = CatalogEntry.create!(
      workspace: workspace, catalog_type: list_type,
      name: "List Entry", slug: "list_entry"
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      entry.assign_validated_attributes!({ "tags" => "not_an_array" })
    end
    assert_match(/Tags must be an array of strings/, error.message)
  end

  test "assign_validated_attributes! accepts valid list values" do
    workspace = workspaces(:slack_workspace_one)
    list_type = CatalogType.create!(
      workspace: workspace, name: "List Test 2", slug: "list_test_2",
      kind: CatalogType::KIND_CUSTOM, position: 99
    )
    list_type.catalog_attribute_definitions.create!(
      slug: "tags", name: "Tags",
      attribute_type: CatalogAttributeDefinition::TYPE_LIST,
      required: false, position: 1, config: {}
    )
    entry = CatalogEntry.create!(
      workspace: workspace, catalog_type: list_type,
      name: "List Entry 2", slug: "list_entry_2"
    )

    scalar, _ref = entry.assign_validated_attributes!({ "tags" => [ "ruby", "rails" ] })
    assert_equal [ "ruby", "rails" ], scalar["tags"]
  end

  test "assign_validated_attributes! validates number is numeric" do
    workspace = workspaces(:slack_workspace_one)
    num_type = CatalogType.create!(
      workspace: workspace, name: "Num Test", slug: "num_test",
      kind: CatalogType::KIND_CUSTOM, position: 99
    )
    num_type.catalog_attribute_definitions.create!(
      slug: "port", name: "Port",
      attribute_type: CatalogAttributeDefinition::TYPE_NUMBER,
      required: false, position: 1, config: {}
    )
    entry = CatalogEntry.create!(
      workspace: workspace, catalog_type: num_type,
      name: "Num Entry", slug: "num_entry"
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      entry.assign_validated_attributes!({ "port" => "not_a_number" })
    end
    assert_match(/Port must be a number/, error.message)
  end

  test "assign_validated_attributes! accepts valid numeric values" do
    workspace = workspaces(:slack_workspace_one)
    num_type = CatalogType.create!(
      workspace: workspace, name: "Num Test 2", slug: "num_test_2",
      kind: CatalogType::KIND_CUSTOM, position: 99
    )
    num_type.catalog_attribute_definitions.create!(
      slug: "port", name: "Port",
      attribute_type: CatalogAttributeDefinition::TYPE_NUMBER,
      required: false, position: 1, config: {}
    )
    entry = CatalogEntry.create!(
      workspace: workspace, catalog_type: num_type,
      name: "Num Entry 2", slug: "num_entry_2"
    )

    scalar, _ref = entry.assign_validated_attributes!({ "port" => 8080 })
    assert_equal 8080, scalar["port"]

    scalar, _ref = entry.assign_validated_attributes!({ "port" => "3000" })
    assert_equal "3000", scalar["port"]
  end

  # Assign validated attributes, required fields

  test "assign_validated_attributes! enforces required fields" do
    acme = catalog_entries(:vendor_acme)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      acme.assign_validated_attributes!({ "tier" => "Gold" })
    end
    assert_match(/Contact Email is required/, error.message)
  end

  test "assign_validated_attributes! accepts valid required fields" do
    acme = catalog_entries(:vendor_acme)

    scalar, _ref = acme.assign_validated_attributes!({
      "contact_email" => "new@example.com",
      "tier" => "Silver"
    })
    assert_equal "new@example.com", scalar["contact_email"]
  end

  # Sync references

  test "sync_references! creates new relationships" do
    auth = catalog_entries(:auth_service)
    platform_team = catalog_entries(:platform_team)

    CatalogEntryRelationship.where(source_entry_id: auth.id).delete_all

    auth.sync_references!({ "owner_team" => platform_team.id })

    rel = auth.outgoing_relationships.find_by!(catalog_attribute_definition: catalog_attribute_definitions(:service_owner_team))
    assert_equal platform_team, rel.target_entry
  end

  test "sync_references! updates existing relationships" do
    auth = catalog_entries(:auth_service)

    # Create a new team entry to point to
    new_team = CatalogEntry.create!(
      workspace: workspaces(:slack_workspace_one),
      catalog_type: catalog_types(:team_ws1),
      name: "New Team",
      slug: "new_team"
    )

    auth.sync_references!({ "owner_team" => new_team.id })

    rel = auth.outgoing_relationships.find_by!(catalog_attribute_definition: catalog_attribute_definitions(:service_owner_team))
    assert_equal new_team, rel.target_entry
  end

  test "sync_references! removes relationships when value is blank" do
    auth = catalog_entries(:auth_service)
    assert auth.outgoing_relationships.where(catalog_attribute_definition: catalog_attribute_definitions(:service_owner_team)).exists?

    auth.sync_references!({ "owner_team" => nil })

    assert_not auth.outgoing_relationships.where(catalog_attribute_definition: catalog_attribute_definitions(:service_owner_team)).exists?
  end

  # Soft delete

  test "soft_delete! sets deleted_at" do
    entry = catalog_entries(:platform_team)
    assert_nil entry.deleted_at

    entry.soft_delete!
    assert_not_nil entry.reload.deleted_at
  end

  test "soft_delete! destroys outgoing relationships" do
    auth = catalog_entries(:auth_service)
    assert auth.outgoing_relationships.exists?

    auth.soft_delete!
    assert_not auth.outgoing_relationships.exists?
  end

  test "soft_delete! destroys incoming relationships" do
    platform_team = catalog_entries(:platform_team)
    assert platform_team.incoming_relationships.exists?

    platform_team.soft_delete!
    assert_not platform_team.incoming_relationships.exists?
  end

  # Slug immutability

  test "slug cannot be changed after creation" do
    entry = catalog_entries(:platform_team)
    entry.slug = "renamed_slug"
    assert_not entry.valid?
    assert_includes entry.errors[:slug], "cannot be changed after creation"
  end

  # Search scope

  test "search scope filters by name" do
    results = CatalogEntry.search("auth")
    assert_includes results, catalog_entries(:auth_service)
    assert_not_includes results, catalog_entries(:platform_team)
  end

  # External identity validations

  test "external identity valid when both external_id and source present" do
    entry = CatalogEntry.new(
      workspace: workspaces(:slack_workspace_one),
      catalog_type: catalog_types(:team_ws1),
      name: "Full External Entry",
      slug: "full_external_entry",
      external_id: "ext-456",
      source: "pagerduty"
    )
    assert entry.valid?
  end

  test "external identity valid when neither external_id nor source present" do
    entry = CatalogEntry.new(
      workspace: workspaces(:slack_workspace_one),
      catalog_type: catalog_types(:team_ws1),
      name: "No External",
      slug: "no_external"
    )
    assert entry.valid?
  end

  test "external_id without source is invalid" do
    entry = CatalogEntry.new(
      workspace: workspaces(:slack_workspace_one),
      catalog_type: catalog_types(:team_ws1),
      name: "Bad External",
      slug: "bad_external",
      external_id: "ext-123"
    )
    assert_not entry.valid?
    assert_includes entry.errors[:source], "is required when external_id is set"
  end

  test "source without external_id is invalid" do
    entry = CatalogEntry.new(
      workspace: workspaces(:slack_workspace_one),
      catalog_type: catalog_types(:team_ws1),
      name: "Bad Source",
      slug: "bad_source",
      source: "github"
    )
    assert_not entry.valid?
    assert_includes entry.errors[:external_id], "is required when source is set"
  end
end
