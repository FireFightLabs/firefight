require "test_helper"

class Catalogue::TypeServiceTest < ActiveSupport::TestCase
  fixtures :workspaces, :catalog_types, :catalog_attribute_definitions, :catalog_entries, :catalog_entry_relationships

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @service = Catalogue::TypeService.new(@workspace)
  end

  # ============================================================================
  # CREATE
  # ============================================================================

  test "create creates custom type with correct slug, position, and kind" do
    type = @service.create(name: "Infrastructure", description: "Infra components", icon: "server", color: "#FF5733")

    assert type.persisted?
    assert_equal "infrastructure", type.slug
    assert_equal CatalogType::KIND_CUSTOM, type.kind
    assert_equal "Infrastructure", type.name
    assert_equal "Infra components", type.description
    assert_equal "server", type.icon
    assert_equal "#FF5733", type.color
    assert_equal @workspace, type.workspace
    assert type.position > 0
  end

  test "create sets position after existing types" do
    max_position = @workspace.catalog_types.maximum(:position)
    type = @service.create(name: "New Type")

    assert_equal max_position + 1, type.position
  end

  test "create with attribute_definitions creates nested definitions" do
    type = @service.create(
      name: "Widget",
      attribute_definitions: [
        { name: "Color", attribute_type: CatalogAttributeDefinition::TYPE_TEXT, required: false },
        { name: "Weight", attribute_type: CatalogAttributeDefinition::TYPE_NUMBER, required: true }
      ]
    )

    assert type.persisted?
    assert_equal 2, type.catalog_attribute_definitions.count

    color_def = type.catalog_attribute_definitions.find_by!(key: "color")
    assert_equal "Color", color_def.name
    assert_equal CatalogAttributeDefinition::TYPE_TEXT, color_def.attribute_type
    assert_equal false, color_def.required

    weight_def = type.catalog_attribute_definitions.find_by!(key: "weight")
    assert_equal "Weight", weight_def.name
    assert_equal CatalogAttributeDefinition::TYPE_NUMBER, weight_def.attribute_type
    assert_equal true, weight_def.required
  end

  test "create wraps in transaction -- attribute sync failure rolls back type creation" do
    CatalogType.any_instance.stubs(:sync_attribute_definitions!).raises(ActiveRecord::RecordInvalid.new(CatalogType.new))

    assert_no_difference -> { CatalogType.count } do
      assert_raises(ActiveRecord::RecordInvalid) do
        @service.create(
          name: "Transactional Type",
          attribute_definitions: [
            { name: "Broken", attribute_type: CatalogAttributeDefinition::TYPE_TEXT }
          ]
        )
      end
    end

    assert_nil CatalogType.find_by(slug: "transactional_type")
  end

  # ============================================================================
  # UPDATE
  # ============================================================================

  test "update updates type fields" do
    vendor = catalog_types(:custom_vendor_ws1)

    result = @service.update(vendor, attrs: { name: "Updated Vendor", description: "New description" })

    vendor.reload
    assert_equal "Updated Vendor", vendor.name
    assert_equal "New description", vendor.description
    assert_equal vendor, result
  end

  test "update with attribute_definitions syncs definitions" do
    vendor = catalog_types(:custom_vendor_ws1)
    existing_attr = catalog_attribute_definitions(:vendor_name_attr)

    @service.update(
      vendor,
      attrs: { name: "Vendor" },
      attribute_definitions: [
        { id: existing_attr.id, name: "Primary Email", attribute_type: CatalogAttributeDefinition::TYPE_TEXT, required: true },
        { id: catalog_attribute_definitions(:vendor_tier).id, name: "Tier", attribute_type: CatalogAttributeDefinition::TYPE_SELECT, config: { "options" => [ "Gold", "Silver", "Bronze" ] } },
        { name: "Website URL", attribute_type: CatalogAttributeDefinition::TYPE_TEXT, required: false }
      ]
    )

    existing_attr.reload
    assert_equal "Primary Email", existing_attr.name

    new_def = vendor.catalog_attribute_definitions.find_by!(key: "website_url")
    assert_equal "Website URL", new_def.name
  end

  test "update wraps in transaction -- attribute sync failure rolls back type update" do
    vendor = catalog_types(:custom_vendor_ws1)
    original_name = vendor.name

    CatalogType.any_instance.stubs(:sync_attribute_definitions!).raises(ActiveRecord::RecordNotDestroyed.new("Sync failed"))

    assert_raises(ActiveRecord::RecordNotDestroyed) do
      @service.update(
        vendor,
        attrs: { name: "Should Not Persist" },
        attribute_definitions: [
          { name: "Broken", attribute_type: CatalogAttributeDefinition::TYPE_TEXT }
        ]
      )
    end

    assert_equal original_name, vendor.reload.name
  end

  # ============================================================================
  # DELETE
  # ============================================================================

  test "delete soft-deletes custom types" do
    vendor = catalog_types(:custom_vendor_ws1)
    assert_nil vendor.deleted_at

    @service.delete(vendor)

    assert_not_nil vendor.reload.deleted_at
  end

  test "delete rejects system type deletion" do
    team = catalog_types(:team_ws1)

    assert_raises(ActiveRecord::RecordNotDestroyed) do
      @service.delete(team)
    end

    assert_nil team.reload.deleted_at
  end
end
