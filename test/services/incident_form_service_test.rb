require "test_helper"

class IncidentFormServiceTest < ActiveSupport::TestCase
  fixtures :workspaces, :catalog_types, :incident_forms, :incident_form_fields, :incident_field_definitions

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @service = IncidentFormService.new(@workspace)
  end

  test "add_custom_field appends field to form" do
    form = incident_forms(:resolve_form_ws1)
    field_definition = incident_field_definitions(:affected_services_ws1)

    assert_difference -> { form.incident_form_fields.count }, 1 do
      @service.add_custom_field(form, field_definition)
    end

    added_field = form.incident_form_fields.find_by!(incident_field_definition: field_definition)
    assert_equal 5, added_field.position
    assert_equal IncidentFormField::FIELD_SOURCE_KIND_CUSTOM, added_field.field_source_kind
  end

  test "move_down swaps positions" do
    form_field = incident_form_fields(:declare_name_field_ws1)

    @service.move_down(form_field)

    assert_equal 2, form_field.reload.position
    assert_equal 1, incident_form_fields(:declare_severity_field_ws1).reload.position
  end

  test "a locked field keeps both its required mode and its visibility" do
    form_field = incident_form_fields(:declare_severity_field_ws1)

    @service.update_field(
      form_field,
      visibility_mode: IncidentFormField::VISIBILITY_MODE_HIDDEN,
      required_mode: IncidentFormField::REQUIRED_MODE_OPTIONAL
    )

    # Severity is NOT NULL on incidents, so a form that hides it can never be
    # submitted. Visibility is locked wherever required is.
    form_field.reload
    assert_equal IncidentFormField::VISIBILITY_MODE_VISIBLE, form_field.visibility_mode
    assert_equal IncidentFormField::REQUIRED_MODE_FIXED_REQUIRED, form_field.required_mode
  end
end
