require "test_helper"

class IncidentFieldDefinitionTest < ActiveSupport::TestCase
  fixtures :workspaces, :catalog_types, :incident_field_definitions

  test "fixed select fields require options" do
    field = IncidentFieldDefinition.new(
      workspace: workspaces(:slack_workspace_one),
      key: "impact_area",
      name: "Impact Area",
      field_type: IncidentFieldDefinition::TYPE_SINGLE_SELECT,
      option_source: IncidentFieldDefinition::OPTION_SOURCE_FIXED,
      position: 3,
      config: {}
    )

    assert_not field.valid?
    assert_includes field.errors[:config], "must include non-empty options for fixed select fields"
  end

  test "catalog-backed fields must reference an active catalog type" do
    field = IncidentFieldDefinition.new(
      workspace: workspaces(:slack_workspace_one),
      key: "impacted_service",
      name: "Impacted Service",
      field_type: IncidentFieldDefinition::TYPE_CATALOG_REFERENCE,
      option_source: IncidentFieldDefinition::OPTION_SOURCE_CATALOG,
      position: 3,
      config: { "catalog_type_id" => "missing" }
    )

    assert_not field.valid?
    assert_includes field.errors[:config], "must reference an active catalog type in the workspace"
  end

  test "key is immutable after creation" do
    field = incident_field_definitions(:customer_tier_ws1)
    field.key = "segment"

    assert_not field.valid?
    assert_includes field.errors[:key], "cannot be changed after creation"
  end
end
