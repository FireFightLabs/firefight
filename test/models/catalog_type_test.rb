require "test_helper"

class CatalogTypeTest < ActiveSupport::TestCase
  # Basic validations

  test "requires name" do
    ct = CatalogType.new(
      workspace: workspaces(:slack_workspace_one),
      slug: "test_type",
      kind: CatalogType::KIND_CUSTOM,
      position: 10
    )
    assert_not ct.valid?
    assert_includes ct.errors[:name], "can't be blank"
  end

  test "requires slug" do
    ct = CatalogType.new(
      workspace: workspaces(:slack_workspace_one),
      name: "Test Type",
      kind: CatalogType::KIND_CUSTOM,
      position: 10
    )
    assert_not ct.valid?
    assert_includes ct.errors[:slug], "can't be blank"
  end

  test "requires kind" do
    ct = CatalogType.new(
      workspace: workspaces(:slack_workspace_one),
      name: "Test Type",
      slug: "test_type",
      position: 10
    )
    assert_not ct.valid?
    assert_includes ct.errors[:kind], "can't be blank"
  end

  test "requires position" do
    ct = CatalogType.new(
      workspace: workspaces(:slack_workspace_one),
      name: "Test Type",
      slug: "test_type",
      kind: CatalogType::KIND_CUSTOM
    )
    assert_not ct.valid?
    assert_includes ct.errors[:position], "can't be blank"
  end

  test "kind must be system or custom" do
    ct = CatalogType.new(
      workspace: workspaces(:slack_workspace_one),
      name: "Test Type",
      slug: "test_type",
      kind: "invalid",
      position: 10
    )
    assert_not ct.valid?
    assert_includes ct.errors[:kind], "is not included in the list"
  end

  # Slug uniqueness

  test "slug must be unique within workspace" do
    existing = catalog_types(:custom_vendor_ws1)
    duplicate = CatalogType.new(
      workspace: existing.workspace,
      name: "Another Vendor",
      slug: existing.slug,
      kind: CatalogType::KIND_CUSTOM,
      position: 99
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:slug], "has already been taken"
  end

  test "slug can be same across different workspaces" do
    ct = CatalogType.new(
      workspace: workspaces(:slack_workspace_two),
      name: "Vendor",
      slug: "vendor",
      kind: CatalogType::KIND_CUSTOM,
      position: 10
    )
    assert ct.valid?
  end

  # System key validations

  test "system key required for system types" do
    ct = CatalogType.new(
      workspace: workspaces(:slack_workspace_one),
      name: "System Type",
      slug: "sys_test",
      kind: CatalogType::KIND_SYSTEM,
      position: 10
    )
    assert_not ct.valid?
    assert_includes ct.errors[:system_key], "must be present for system types"
  end

  test "system key must be null for custom types" do
    ct = CatalogType.new(
      workspace: workspaces(:slack_workspace_one),
      name: "Custom Type",
      slug: "custom_test",
      kind: CatalogType::KIND_CUSTOM,
      system_key: CatalogType::SYSTEM_KEY_SERVICE,
      position: 10
    )
    assert_not ct.valid?
    assert_includes ct.errors[:system_key], "must be blank for custom types"
  end

  test "system key must be unique per workspace" do
    duplicate = CatalogType.new(
      workspace: workspaces(:slack_workspace_one),
      name: "Another Team",
      slug: "another_team",
      kind: CatalogType::KIND_SYSTEM,
      system_key: CatalogType::SYSTEM_KEY_TEAM,
      position: 99
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:system_key], "has already been taken"
  end

  # Reserved slugs

  test "custom types cannot use reserved slugs" do
    CatalogType::RESERVED_SLUGS.each do |reserved_slug|
      ct = CatalogType.new(
        workspace: workspaces(:slack_workspace_two),
        name: "Custom #{reserved_slug}",
        slug: reserved_slug,
        kind: CatalogType::KIND_CUSTOM,
        position: 10
      )
      assert_not ct.valid?, "Expected slug '#{reserved_slug}' to be rejected for custom types"
      assert_includes ct.errors[:slug], "is reserved for system types"
    end
  end

  # System fields immutable on update

  test "system type slug is immutable on update" do
    team = catalog_types(:team_ws1)
    team.slug = "renamed_team"
    assert_not team.valid?
    assert_includes team.errors[:slug], "cannot be changed for system types"
  end

  test "system type system_key is immutable on update" do
    team = catalog_types(:team_ws1)
    team.system_key = CatalogType::SYSTEM_KEY_SERVICE
    assert_not team.valid?
    assert_includes team.errors[:system_key], "cannot be changed for system types"
  end

  test "custom type slug can be changed on update" do
    vendor = catalog_types(:custom_vendor_ws1)
    vendor.slug = "renamed_vendor"
    assert vendor.valid?
  end

  # Kind helpers

  test "system? returns true for system types" do
    assert catalog_types(:team_ws1).system?
  end

  test "system? returns false for custom types" do
    assert_not catalog_types(:custom_vendor_ws1).system?
  end

  test "custom? returns true for custom types" do
    assert catalog_types(:custom_vendor_ws1).custom?
  end

  test "custom? returns false for system types" do
    assert_not catalog_types(:team_ws1).custom?
  end

  # Scopes

  test "active scope excludes deleted types" do
    vendor = catalog_types(:custom_vendor_ws1)
    vendor.update!(deleted_at: Time.current)

    active_types = CatalogType.active
    assert_not_includes active_types, vendor
    assert_includes active_types, catalog_types(:team_ws1)
  end

  test "with_entry_counts returns correct counts including zero-entry types" do
    workspace = workspaces(:slack_workspace_one)
    types_with_counts = workspace.catalog_types.active.with_entry_counts

    team_type = types_with_counts.find { |t| t.id == catalog_types(:team_ws1).id }
    service_type = types_with_counts.find { |t| t.id == catalog_types(:service_ws1).id }
    functionality_type = types_with_counts.find { |t| t.id == catalog_types(:functionality_ws1).id }

    assert_equal 1, team_type.entry_count
    assert_equal 1, service_type.entry_count
    assert_equal 0, functionality_type.entry_count
  end

  # Soft delete

  test "soft_delete! rejects system types" do
    team = catalog_types(:team_ws1)
    error = assert_raises(ActiveRecord::RecordNotDestroyed) { team.soft_delete! }
    assert_equal team.deletion_blocked_reason, error.message
    assert_match(/built-in type/, error.message)
  end

  test "a type another type's attribute points at cannot be deleted, and the reason names the attribute" do
    vendor = catalog_types(:custom_vendor_ws1)
    service = catalog_types(:service_ws1)
    service.catalog_attribute_definitions.create!(
      name: "Vendor", slug: "vendor", attribute_type: CatalogAttributeDefinition::TYPE_REFERENCE,
      position: 99, config: { "reference_type_id" => vendor.id }
    )

    reason = vendor.deletion_blocked_reason
    assert_equal "Vendor is referenced by the Vendor attribute on Service. Remove that attribute before deleting the type.", reason
    error = assert_raises(ActiveRecord::RecordNotDestroyed) { vendor.soft_delete! }
    assert_equal reason, error.message
    assert_nil vendor.reload.deleted_at
  end

  test "soft_delete! sets deleted_at on custom types" do
    vendor = catalog_types(:custom_vendor_ws1)
    vendor.soft_delete!
    assert_not_nil vendor.reload.deleted_at
  end

  test "soft_delete! soft-deletes entries belonging to the type" do
    vendor = catalog_types(:custom_vendor_ws1)
    acme = catalog_entries(:vendor_acme)
    assert_nil acme.deleted_at

    vendor.soft_delete!
    assert_not_nil acme.reload.deleted_at
  end

  test "soft_delete! cleans up relationships for affected entries" do
    service_type = catalog_types(:service_ws1)

    # The service_ws1 type has auth_service, which has the auth_service_owner relationship
    # We can't soft delete a system type, so test with a custom type that has relationships instead.
    # Create a custom type setup with relationships for this test.
    workspace = workspaces(:slack_workspace_one)
    custom_type = CatalogType.create!(
      workspace: workspace, name: "Deletable", slug: "deletable",
      kind: CatalogType::KIND_CUSTOM, position: 99
    )
    entry = CatalogEntry.create!(
      workspace: workspace, catalog_type: custom_type,
      name: "Del Entry", slug: "del_entry"
    )
    rel = CatalogEntryRelationship.create!(
      workspace: workspace,
      source_entry: entry,
      target_entry: catalog_entries(:platform_team),
      catalog_attribute_definition: catalog_attribute_definitions(:service_owner_team)
    )

    custom_type.soft_delete!
    assert_not CatalogEntryRelationship.exists?(rel.id)
  end

  # Sync attribute definitions

  test "sync_attribute_definitions! creates new definitions" do
    vendor = catalog_types(:custom_vendor_ws1)
    initial_count = vendor.catalog_attribute_definitions.count

    vendor.sync_attribute_definitions!([
      { id: catalog_attribute_definitions(:vendor_name_attr).id, name: "Contact Email", attribute_type: CatalogAttributeDefinition::TYPE_TEXT, required: true },
      { id: catalog_attribute_definitions(:vendor_tier).id, name: "Tier", attribute_type: CatalogAttributeDefinition::TYPE_SELECT, config: { "options" => [ "Gold", "Silver", "Bronze" ] } },
      { name: "Website", attribute_type: CatalogAttributeDefinition::TYPE_TEXT, required: false }
    ])

    assert_equal initial_count + 1, vendor.catalog_attribute_definitions.reload.count
    new_def = vendor.catalog_attribute_definitions.find_by!(slug: "website")
    assert_equal "Website", new_def.name
    assert_equal CatalogAttributeDefinition::TYPE_TEXT, new_def.attribute_type
  end

  test "sync_attribute_definitions! updates existing definitions" do
    vendor = catalog_types(:custom_vendor_ws1)
    attr_def = catalog_attribute_definitions(:vendor_name_attr)

    vendor.sync_attribute_definitions!([
      { id: attr_def.id, name: "Primary Contact Email", attribute_type: CatalogAttributeDefinition::TYPE_TEXT, required: false },
      { id: catalog_attribute_definitions(:vendor_tier).id, name: "Tier", attribute_type: CatalogAttributeDefinition::TYPE_SELECT, config: { "options" => [ "Gold", "Silver", "Bronze" ] } }
    ])

    attr_def.reload
    assert_equal "Primary Contact Email", attr_def.name
    assert_equal false, attr_def.required
  end

  test "sync_attribute_definitions! rejects removal of definitions used by entries" do
    vendor = catalog_types(:custom_vendor_ws1)

    # vendor_name_attr (contact_email) is used by vendor_acme entry
    error = assert_raises(ActiveRecord::RecordNotDestroyed) do
      vendor.sync_attribute_definitions!([
        { id: catalog_attribute_definitions(:vendor_tier).id, name: "Tier", attribute_type: CatalogAttributeDefinition::TYPE_SELECT, config: { "options" => [ "Gold", "Silver", "Bronze" ] } }
      ])
    end
    assert_match(/Contact Email/, error.message)
  end

  # Reference entry options

  test "reference_entry_options returns entries from referenced types" do
    service_type = catalog_types(:service_ws1)
    options = service_type.reference_entry_options

    assert options.any?, "Expected reference entry options for service type"
    team_entry = options.find { |o| o[:id] == catalog_entries(:platform_team).id }
    assert_not_nil team_entry
    assert_equal "Platform Team", team_entry[:name]
    assert_equal catalog_types(:team_ws1).id, team_entry[:typeId]
  end

  test "reference_entry_options returns empty for types without reference attributes" do
    team_type = catalog_types(:team_ws1)
    options = team_type.reference_entry_options
    assert_empty options
  end

  test "reference_entry_options excludes deleted entries" do
    service_type = catalog_types(:service_ws1)
    options = service_type.reference_entry_options

    deleted_entry_ids = options.map { |o| o[:id] }
    assert_not_includes deleted_entry_ids, catalog_entries(:deleted_entry).id
  end

  # Schema evolution guards

  test "reference_type_id cannot be changed on existing reference attribute" do
    service_type = catalog_types(:service_ws1)
    owner_attr = catalog_attribute_definitions(:service_owner_team)
    environment_type = catalog_types(:environment_ws1)

    error = assert_raises(ActiveRecord::RecordNotDestroyed) do
      service_type.sync_attribute_definitions!([
        { id: catalog_attribute_definitions(:service_description).id, name: "Description", attribute_type: CatalogAttributeDefinition::TYPE_TEXT },
        { id: owner_attr.id, name: "Owner Team", attribute_type: CatalogAttributeDefinition::TYPE_REFERENCE,
          config: { "reference_type_id" => environment_type.id } },
        { id: catalog_attribute_definitions(:service_tier).id, name: "Tier", attribute_type: CatalogAttributeDefinition::TYPE_SELECT,
          config: { "options" => [ "Critical", "Standard", "Internal" ] } }
      ])
    end

    assert_match(/Cannot change reference target type/, error.message)
  end

  test "system types can gain new custom attributes" do
    team_type = catalog_types(:team_ws1)
    initial_count = team_type.catalog_attribute_definitions.count

    team_type.sync_attribute_definitions!([
      { id: catalog_attribute_definitions(:team_description).id, name: "Description", attribute_type: CatalogAttributeDefinition::TYPE_TEXT },
      { id: catalog_attribute_definitions(:team_slack_channel).id, name: "Slack Channel", attribute_type: CatalogAttributeDefinition::TYPE_TEXT },
      { name: "On-Call Rotation", attribute_type: CatalogAttributeDefinition::TYPE_TEXT, required: false }
    ])

    assert_equal initial_count + 1, team_type.catalog_attribute_definitions.reload.count
    new_attr = team_type.catalog_attribute_definitions.find_by!(slug: "oncall_rotation")
    assert_equal "On-Call Rotation", new_attr.name
    assert_equal CatalogAttributeDefinition::TYPE_TEXT, new_attr.attribute_type
  end
end
