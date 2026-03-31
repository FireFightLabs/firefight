require "test_helper"

class CatalogTypeWriteTest < ActiveSupport::TestCase
  fixtures :workspaces, :catalog_types, :catalog_attribute_definitions, :catalog_entries, :catalog_entry_relationships

  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  # ============================================================================
  # CREATE_CUSTOM!
  # ============================================================================

  test "create_custom! creates custom type with correct slug, position, and kind" do
    type = CatalogType.create_custom!(
      workspace: @workspace, name: "Infrastructure",
      description: "Infra components", icon: "server", color: "#FF5733"
    )

    assert type.persisted?
    assert_equal "infrastructure", type.slug
    assert_equal CatalogType::KIND_CUSTOM, type.kind
    assert_equal "Infrastructure", type.name
    assert_equal @workspace, type.workspace
    assert type.position > 0
  end

  test "create_custom! sets position after existing types" do
    max_position = @workspace.catalog_types.maximum(:position)
    type = CatalogType.create_custom!(workspace: @workspace, name: "New Type")

    assert_equal max_position + 1, type.position
  end

  test "create_custom! with attribute_definitions creates nested definitions" do
    type = CatalogType.create_custom!(
      workspace: @workspace, name: "Widget",
      attribute_definitions: [
        { name: "Color", attribute_type: CatalogAttributeDefinition::TYPE_TEXT, required: false },
        { name: "Weight", attribute_type: CatalogAttributeDefinition::TYPE_NUMBER, required: true }
      ]
    )

    assert_equal 2, type.catalog_attribute_definitions.count
    assert type.catalog_attribute_definitions.find_by!(key: "color").present?
    assert type.catalog_attribute_definitions.find_by!(key: "weight").required
  end

  test "create_custom! wraps in transaction -- attribute sync failure rolls back type creation" do
    CatalogType.any_instance.stubs(:sync_attribute_definitions!).raises(ActiveRecord::RecordInvalid.new(CatalogType.new))

    assert_no_difference -> { CatalogType.count } do
      assert_raises(ActiveRecord::RecordInvalid) do
        CatalogType.create_custom!(
          workspace: @workspace, name: "Transactional Type",
          attribute_definitions: [
            { name: "Broken", attribute_type: CatalogAttributeDefinition::TYPE_TEXT }
          ]
        )
      end
    end
  end

  # ============================================================================
  # UPDATE_WITH_DEFINITIONS!
  # ============================================================================

  test "update_with_definitions! updates type fields" do
    vendor = catalog_types(:custom_vendor_ws1)
    vendor.update_with_definitions!({ name: "Updated Vendor", description: "New description" })

    assert_equal "Updated Vendor", vendor.reload.name
    assert_equal "New description", vendor.description
  end

  test "update_with_definitions! syncs attribute definitions" do
    vendor = catalog_types(:custom_vendor_ws1)
    existing_attr = catalog_attribute_definitions(:vendor_name_attr)

    vendor.update_with_definitions!(
      { name: "Vendor" },
      attribute_definitions: [
        { id: existing_attr.id, name: "Primary Email", attribute_type: CatalogAttributeDefinition::TYPE_TEXT, required: true },
        { id: catalog_attribute_definitions(:vendor_tier).id, name: "Tier", attribute_type: CatalogAttributeDefinition::TYPE_SELECT, config: { "options" => [ "Gold", "Silver", "Bronze" ] } },
        { name: "Website URL", attribute_type: CatalogAttributeDefinition::TYPE_TEXT, required: false }
      ]
    )

    assert_equal "Primary Email", existing_attr.reload.name
    assert vendor.catalog_attribute_definitions.find_by!(key: "website_url").present?
  end

  test "update_with_definitions! wraps in transaction -- attribute sync failure rolls back" do
    vendor = catalog_types(:custom_vendor_ws1)
    original_name = vendor.name

    CatalogType.any_instance.stubs(:sync_attribute_definitions!).raises(ActiveRecord::RecordNotDestroyed.new("Sync failed"))

    assert_raises(ActiveRecord::RecordNotDestroyed) do
      vendor.update_with_definitions!(
        { name: "Should Not Persist" },
        attribute_definitions: [ { name: "Broken", attribute_type: CatalogAttributeDefinition::TYPE_TEXT } ]
      )
    end

    assert_equal original_name, vendor.reload.name
  end

  # ============================================================================
  # SOFT_DELETE!
  # ============================================================================

  test "soft_delete! soft-deletes custom types" do
    vendor = catalog_types(:custom_vendor_ws1)
    vendor.soft_delete!
    assert_not_nil vendor.reload.deleted_at
  end

  test "soft_delete! rejects system type deletion" do
    team = catalog_types(:team_ws1)
    assert_raises(ActiveRecord::RecordNotDestroyed) { team.soft_delete! }
    assert_nil team.reload.deleted_at
  end
end
