require "test_helper"

class CatalogueControllerTest < ActionDispatch::IntegrationTest
  fixtures :workspaces, :users, :workspace_memberships,
           :catalog_types, :catalog_attribute_definitions, :catalog_entries, :catalog_entry_relationships

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @user = users(:alice)
    sign_in(@user, @workspace)
  end

  # ============================================================================
  # REGRESSION: ATTRIBUTE CONFIG PERSISTENCE
  # ============================================================================

  test "create_type persists select config from frontend-shaped payload" do
    assert_difference -> { CatalogType.count }, 1 do
      post "/app/catalogue/types", params: {
        name: "Region",
        description: "Deployment regions",
        color: "#3B82F6",
        icon: "box",
        attribute_definitions: [
          {
            name: "Tier",
            attributeType: "select",
            required: false,
            options: [ "Primary", "Secondary", "DR" ]
          }
        ]
      }
    end

    type = CatalogType.find_by!(slug: "region")
    attr_def = type.catalog_attribute_definitions.find_by!(key: "tier")
    assert_equal CatalogAttributeDefinition::TYPE_SELECT, attr_def.attribute_type
    assert_equal [ "Primary", "Secondary", "DR" ], attr_def.config["options"]
  end

  test "create_type persists reference config from frontend-shaped payload" do
    team_type = catalog_types(:team_ws1)

    assert_difference -> { CatalogType.count }, 1 do
      post "/app/catalogue/types", params: {
        name: "Runbook",
        description: "Operational runbooks",
        color: "#10B981",
        icon: "box",
        attribute_definitions: [
          {
            name: "Owner Team",
            attributeType: "reference",
            required: false,
            referenceTypeId: team_type.id
          }
        ]
      }
    end

    type = CatalogType.find_by!(slug: "runbook")
    attr_def = type.catalog_attribute_definitions.find_by!(key: "owner_team")
    assert_equal CatalogAttributeDefinition::TYPE_REFERENCE, attr_def.attribute_type
    assert_equal team_type.id, attr_def.config["reference_type_id"]
  end

  test "update_type preserves config when updating attributes" do
    type = catalog_types(:custom_vendor_ws1)
    email_def = catalog_attribute_definitions(:vendor_name_attr)
    tier_def = catalog_attribute_definitions(:vendor_tier)

    patch "/app/catalogue/types/#{type.id}", params: {
      name: "Vendor",
      description: "Updated description",
      color: "#EC4899",
      icon: "box",
      attribute_definitions: [
        {
          id: email_def.id,
          name: "Contact Email",
          attributeType: "text",
          required: true
        },
        {
          id: tier_def.id,
          name: "Tier Level",
          attributeType: "select",
          required: true,
          options: [ "Gold", "Silver", "Bronze", "Free" ]
        }
      ]
    }

    tier_def.reload
    assert_equal "Tier Level", tier_def.name
    assert_equal [ "Gold", "Silver", "Bronze", "Free" ], tier_def.config["options"]
    assert tier_def.required
  end

  # ============================================================================
  # REGRESSION: ICON PERSISTENCE
  # ============================================================================

  test "create_type persists icon" do
    post "/app/catalogue/types", params: {
      name: "Pipeline",
      description: "CI/CD pipelines",
      color: "#F59E0B",
      icon: "box"
    }

    type = CatalogType.find_by!(slug: "pipeline")
    assert_equal "box", type.icon
  end

  private

  def sign_in(user, workspace)
    ApplicationController.any_instance.stubs(:current_user).returns(user)
    ApplicationController.any_instance.stubs(:current_workspace).returns(workspace)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
  end
end
