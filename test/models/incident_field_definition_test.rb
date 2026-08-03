require "test_helper"

class IncidentFieldDefinitionTest < ActiveSupport::TestCase
  fixtures :workspaces, :catalog_types, :incident_field_definitions, :incident_field_options

  test "fixed select fields require at least one enabled option" do
    field = IncidentFieldDefinition.new(
      workspace: workspaces(:slack_workspace_one),
      key: "impact_area",
      name: "Impact Area",
      field_type: IncidentFieldDefinition::TYPE_SINGLE_SELECT,
      option_source: IncidentFieldDefinition::OPTION_SOURCE_FIXED,
      position: 3
    )

    assert_not field.valid?
    assert_includes field.errors[:base], "must include at least one enabled option for fixed select fields"
  end

  test "a fixed select field with only disabled options is invalid" do
    field = incident_field_definitions(:customer_tier_ws1)
    field.incident_field_options.update_all(disabled_at: Time.current)
    field.incident_field_options.reset

    assert_not field.valid?
    assert_includes field.errors[:base], "must include at least one enabled option for fixed select fields"
  end

  test "catalog-backed fields must reference an active catalog type" do
    field = IncidentFieldDefinition.new(
      workspace: workspaces(:slack_workspace_one),
      key: "impacted_service",
      name: "Impacted Service",
      field_type: IncidentFieldDefinition::TYPE_CATALOG_REFERENCE,
      option_source: IncidentFieldDefinition::OPTION_SOURCE_CATALOG,
      position: 3,
      catalog_type_id: SecureRandom.uuid
    )

    assert_not field.valid?
    assert_includes field.errors[:catalog_type], "must be an active catalog type in the workspace"
  end

  test "key is immutable after creation" do
    field = incident_field_definitions(:customer_tier_ws1)
    field.key = "segment"

    assert_not field.valid?
    assert_includes field.errors[:key], "cannot be changed after creation"
  end

  test "renaming an option leaves the id every reference points at untouched" do
    field = incident_field_definitions(:customer_tier_ws1)
    option = field.incident_field_options.find_by!(label: "Pro")

    field.sync_options!(
      field.incident_field_options.ordered.map do |current|
        { id: current.id, label: current.id == option.id ? "Professional" : current.label }
      end
    )

    assert_equal "Professional", option.reload.label
    assert_equal option.id, field.incident_field_options.find_by!(label: "Professional").id
  end

  test "sync_options! assigns positions from the order it is given" do
    field = incident_field_definitions(:customer_tier_ws1)
    reversed = field.incident_field_options.ordered.reverse.map { |o| { id: o.id, label: o.label } }

    field.sync_options!(reversed)

    assert_equal [ "Free", "Pro", "Enterprise" ], field.incident_field_options.ordered.pluck(:label)
  end
end
