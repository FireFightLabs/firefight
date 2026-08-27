require "test_helper"

class IncidentFormFieldTest < ActiveSupport::TestCase
  test "system fields require a valid system_field_key" do
    field = IncidentFormField.new(
      incident_form: incident_forms(:declare_form_ws1),
      field_source_kind: IncidentFormField::FIELD_SOURCE_KIND_SYSTEM,
      system_field_key: "unknown",
      position: 4,
      visibility_mode: IncidentFormField::VISIBILITY_MODE_VISIBLE,
      required_mode: IncidentFormField::REQUIRED_MODE_OPTIONAL
    )

    assert_not field.valid?
    assert_includes field.errors[:system_field_key], "is not a valid system field"
  end

  test "custom field rows require an incident field definition" do
    field = IncidentFormField.new(
      incident_form: incident_forms(:declare_form_ws1),
      field_source_kind: IncidentFormField::FIELD_SOURCE_KIND_CUSTOM,
      position: 4,
      visibility_mode: IncidentFormField::VISIBILITY_MODE_VISIBLE,
      required_mode: IncidentFormField::REQUIRED_MODE_OPTIONAL
    )

    assert_not field.valid?
    assert_includes field.errors[:base], "custom fields must provide only incident_field_definition_id"
  end
end
