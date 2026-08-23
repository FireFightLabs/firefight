require "test_helper"

class IncidentFormFieldsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @user = users(:alice)
    sign_in(@user, @workspace)
  end

  test "toggling a system field that has no row materializes one" do
    patch incident_form_field_path("default:#{IncidentSystemField::KEY_NAME}"), params: {
      incident_form_id: "default:#{IncidentForm::SLUG_DECLARE}",
      visibility_mode: IncidentFormField::VISIBILITY_MODE_HIDDEN,
      required_mode: IncidentFormField::REQUIRED_MODE_OPTIONAL
    }
    assert_response :redirect

    form = @workspace.incident_forms.find_by!(slug: IncidentForm::SLUG_DECLARE)
    field = form.incident_form_fields.find_by!(system_field_key: IncidentSystemField::KEY_NAME)
    assert_equal IncidentFormField::VISIBILITY_MODE_HIDDEN, field.visibility_mode
  end

  test "toggling the same system field twice updates the row rather than adding another" do
    2.times do |n|
      patch incident_form_field_path("default:#{IncidentSystemField::KEY_SUMMARY}"), params: {
        incident_form_id: "default:#{IncidentForm::SLUG_DECLARE}",
        visibility_mode: n.zero? ? IncidentFormField::VISIBILITY_MODE_HIDDEN : IncidentFormField::VISIBILITY_MODE_VISIBLE,
        required_mode: IncidentFormField::REQUIRED_MODE_OPTIONAL
      }
    end

    form = @workspace.incident_forms.find_by!(slug: IncidentForm::SLUG_DECLARE)
    fields = form.incident_form_fields.where(system_field_key: IncidentSystemField::KEY_SUMMARY)
    assert_equal 1, fields.count
    assert_equal IncidentFormField::VISIBILITY_MODE_VISIBLE, fields.first.visibility_mode
  end

  test "a field the incident cannot be written without refuses to be hidden" do
    patch incident_form_field_path("default:#{IncidentSystemField::KEY_SEVERITY}"), params: {
      incident_form_id: "default:#{IncidentForm::SLUG_DECLARE}",
      visibility_mode: IncidentFormField::VISIBILITY_MODE_HIDDEN,
      required_mode: IncidentFormField::REQUIRED_MODE_OPTIONAL
    }
    assert_response :redirect

    form = @workspace.incident_forms.find_by!(slug: IncidentForm::SLUG_DECLARE)
    field = form.incident_form_fields.find_by!(system_field_key: IncidentSystemField::KEY_SEVERITY)
    assert_equal IncidentFormField::VISIBILITY_MODE_VISIBLE, field.visibility_mode
    assert_equal IncidentFormField::REQUIRED_MODE_FIXED_REQUIRED, field.required_mode
  end

  test "updating a custom field reports the field name instead of erroring" do
    form = @workspace.ensure_incident_form!(IncidentForm::SLUG_DECLARE)
    definition = incident_field_definitions(:customer_tier_ws1)
    field = form.incident_form_fields.create!(
      field_source_kind: IncidentFormField::FIELD_SOURCE_KIND_CUSTOM,
      incident_field_definition: definition,
      position: 99,
      visibility_mode: IncidentFormField::VISIBILITY_MODE_VISIBLE,
      required_mode: IncidentFormField::REQUIRED_MODE_OPTIONAL
    )

    patch incident_form_field_path(field), params: {
      visibility_mode: IncidentFormField::VISIBILITY_MODE_HIDDEN,
      required_mode: IncidentFormField::REQUIRED_MODE_OPTIONAL
    }
    assert_response :redirect
    assert_equal "#{definition.name} was updated.", flash[:notice]
    assert_equal IncidentFormField::VISIBILITY_MODE_HIDDEN, field.reload.visibility_mode
  end

  test "removing a custom field reports its name instead of erroring" do
    form = @workspace.ensure_incident_form!(IncidentForm::SLUG_DECLARE)
    definition = incident_field_definitions(:customer_tier_ws1)
    field = form.incident_form_fields.create!(
      field_source_kind: IncidentFormField::FIELD_SOURCE_KIND_CUSTOM,
      incident_field_definition: definition,
      position: 99,
      visibility_mode: IncidentFormField::VISIBILITY_MODE_VISIBLE,
      required_mode: IncidentFormField::REQUIRED_MODE_OPTIONAL
    )

    delete incident_form_field_path(field)
    assert_response :redirect
    assert_equal "#{definition.name} was removed from the form.", flash[:notice]
    assert_not IncidentFormField.exists?(field.id)
  end

  test "a hidden field stays in the editor so it can be turned back on" do
    patch incident_form_field_path("default:#{IncidentSystemField::KEY_NAME}"), params: {
      incident_form_id: "default:#{IncidentForm::SLUG_DECLARE}",
      visibility_mode: IncidentFormField::VISIBILITY_MODE_HIDDEN,
      required_mode: IncidentFormField::REQUIRED_MODE_OPTIONAL
    }

    get settings_forms_url, headers: inertia_headers
    declare = response.parsed_body.dig("props", "forms").find { |f| f["slug"] == IncidentForm::SLUG_DECLARE }
    name_field = declare["fields"].find { |f| f["systemFieldKey"] == IncidentSystemField::KEY_NAME }

    assert name_field, "a hidden field must still be listed in the editor"
    assert_equal IncidentFormField::VISIBILITY_MODE_HIDDEN, name_field["visibilityMode"]
  end

  test "a hidden field is not resolved for responders" do
    patch incident_form_field_path("default:#{IncidentSystemField::KEY_NAME}"), params: {
      incident_form_id: "default:#{IncidentForm::SLUG_DECLARE}",
      visibility_mode: IncidentFormField::VISIBILITY_MODE_HIDDEN,
      required_mode: IncidentFormField::REQUIRED_MODE_OPTIONAL
    }

    resolved = IncidentFormResolver.new(@workspace).resolve(IncidentForm::SLUG_DECLARE)
    assert_not_includes resolved.map(&:system_field_key), IncidentSystemField::KEY_NAME
  end

  test "the forms page explains why status will not reach responders" do
    get settings_forms_url, headers: inertia_headers

    cancel = response.parsed_body.dig("props", "forms").find { |f| f["slug"] == IncidentForm::SLUG_CANCEL }
    status = cancel["fields"].find { |f| f["systemFieldKey"] == IncidentSystemField::KEY_STATUS }

    assert status, "status must be listed, or its appearance in Slack is inexplicable"
    assert_match "only one canceled status", status["inactiveReason"].to_s
  end

  test "a system field that does not belong to the form is refused" do
    patch incident_form_field_path("default:#{IncidentSystemField::KEY_NEXT_UPDATE}"), params: {
      incident_form_id: "default:#{IncidentForm::SLUG_DECLARE}",
      visibility_mode: IncidentFormField::VISIBILITY_MODE_HIDDEN,
      required_mode: IncidentFormField::REQUIRED_MODE_OPTIONAL
    }

    assert_response :redirect
    assert_match "does not appear on the declare form", flash[:alert]
    assert_not IncidentFormField.exists?(system_field_key: IncidentSystemField::KEY_NEXT_UPDATE)
  end
end
