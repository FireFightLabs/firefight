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
    attr_def = type.catalog_attribute_definitions.find_by!(slug: "tier")
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
    attr_def = type.catalog_attribute_definitions.find_by!(slug: "owner_team")
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

  # ============================================================================
  # REGRESSION: VALIDATION ERROR SHAPE
  # ============================================================================

  test "update_type returns field level errors when the type is invalid" do
    type = catalog_types(:custom_vendor_ws1)

    patch "/app/catalogue/types/#{type.id}", params: {
      name: "",
      description: "Updated description",
      color: "#EC4899",
      icon: "box"
    }

    assert_response :redirect
    assert_equal "Vendor", type.reload.name
    assert_equal [ "can't be blank" ], session["inertia_errors"][:name]
  end

  test "update_type returns a base error when an attribute is still in use" do
    type = catalog_types(:custom_vendor_ws1)
    email_def = catalog_attribute_definitions(:vendor_name_attr)

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
        }
      ]
    }

    assert_response :redirect
    assert catalog_attribute_definitions(:vendor_tier).reload.persisted?
    assert_equal [ "Cannot remove attribute 'Tier' because it is used by active entries" ], session["inertia_errors"][:base]
  end

  test "update_type names the attribute in a base error rather than blaming the type's own fields" do
    type = catalog_types(:custom_vendor_ws1)
    email_def = catalog_attribute_definitions(:vendor_name_attr)
    tier_def = catalog_attribute_definitions(:vendor_tier)

    patch "/app/catalogue/types/#{type.id}", params: {
      name: "Vendor",
      description: "Updated description",
      color: "#EC4899",
      icon: "box",
      attribute_definitions: [
        { id: email_def.id, name: "Contact Email", attributeType: "text", required: true },
        { id: tier_def.id, name: "Tier", attributeType: "select", required: false, options: [ "Gold", "Silver", "Bronze" ] },
        { name: "Region", attributeType: "select", required: false }
      ]
    }

    assert_response :redirect
    assert_nil session["inertia_errors"][:name]
    assert_equal [ "Region: Config must include non-empty options for select attributes" ],
      session["inertia_errors"][:base]
  end

  test "create_entry returns one base error per invalid attribute" do
    assert_no_difference -> { CatalogEntry.count } do
      post "/app/catalogue/vendor/entries", params: { name: "Globex", attributes: { tier: "Platinum" } }
    end

    assert_response :redirect
    assert_equal [ "Contact Email is required", "Tier must be one of: Gold, Silver, Bronze" ],
      session["inertia_errors"][:base]
  end

  test "create_entry returns a blank name on the name field" do
    assert_no_difference -> { CatalogEntry.count } do
      post "/app/catalogue/vendor/entries", params: { name: "", attributes: { contact_email: "hi@globex.com" } }
    end

    assert_response :redirect
    assert_equal [ "can't be blank" ], session["inertia_errors"][:name]
  end

  test "update_entry returns the invalid attribute on base" do
    entry = catalog_entries(:vendor_acme)

    patch "/app/catalogue/entries/#{entry.id}", params: {
      name: "Acme Corp",
      attributes: { contact_email: "support@acme.com", tier: "Platinum" }
    }

    assert_response :redirect
    assert_equal "Gold", entry.reload.entry_attributes["tier"]
    assert_equal [ "Tier must be one of: Gold, Silver, Bronze" ], session["inertia_errors"][:base]
  end

  private

  def sign_in(user, workspace)
    ApplicationController.any_instance.stubs(:current_user).returns(user)
    ApplicationController.any_instance.stubs(:current_workspace).returns(workspace)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
  end
end
