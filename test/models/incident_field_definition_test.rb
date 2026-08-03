require "test_helper"

class IncidentFieldDefinitionTest < ActiveSupport::TestCase
  fixtures :workspaces, :catalog_types, :incident_field_definitions, :incident_field_options

  test "fixed select fields require at least one enabled option" do
    field = IncidentFieldDefinition.new(
      workspace: workspaces(:slack_workspace_one),
      slug: "impact_area",
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
      slug: "impacted_service",
      name: "Impacted Service",
      field_type: IncidentFieldDefinition::TYPE_CATALOG_REFERENCE,
      option_source: IncidentFieldDefinition::OPTION_SOURCE_CATALOG,
      position: 3,
      catalog_type_id: SecureRandom.uuid
    )

    assert_not field.valid?
    assert_includes field.errors[:catalog_type], "must be an active catalog type in the workspace"
  end

  test "every field type maps to exactly one storage kind" do
    kinds = IncidentFieldDefinition::FIELD_TYPES.map do |field_type|
      source = if IncidentFieldDefinition.selectable?(field_type)
        field_type.start_with?("catalog") ? IncidentFieldDefinition::OPTION_SOURCE_CATALOG : IncidentFieldDefinition::OPTION_SOURCE_FIXED
      else
        IncidentFieldDefinition::OPTION_SOURCE_NONE
      end

      IncidentFieldDefinition.new(field_type: field_type, option_source: source).storage_kind
    end

    assert_equal IncidentFieldDefinition::FIELD_TYPES.size, kinds.size
    assert_empty kinds - [
      IncidentFieldDefinition::STORAGE_OPTION,
      IncidentFieldDefinition::STORAGE_CATALOG_ENTRY,
      IncidentFieldDefinition::STORAGE_SCALAR
    ]
  end

  test "a select on a catalogue stores catalog entries, not its own options" do
    field = incident_field_definitions(:customer_tier_ws1)
    assert_equal IncidentFieldDefinition::STORAGE_OPTION, field.storage_kind

    field.option_source = IncidentFieldDefinition::OPTION_SOURCE_CATALOG
    assert_equal IncidentFieldDefinition::STORAGE_CATALOG_ENTRY, field.storage_kind
  end

  test "value_attributes_for puts the entry in the column its storage kind owns" do
    field = incident_field_definitions(:customer_tier_ws1)
    assert_equal({ incident_field_option_id: "abc" }, field.value_attributes_for("abc"))

    field.field_type = IncidentFieldDefinition::TYPE_NUMBER
    field.option_source = IncidentFieldDefinition::OPTION_SOURCE_NONE
    assert_equal({ value_number: 3 }, field.value_attributes_for(3))
  end

  test "slug is immutable after creation" do
    field = incident_field_definitions(:customer_tier_ws1)
    field.slug = "segment"

    assert_not field.valid?
    assert_includes field.errors[:slug], "cannot be changed after creation"
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
