require "test_helper"

class IncidentFormServiceTest < ActiveSupport::TestCase
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

  # Dragging a system field the workspace never customized sends a synthetic
  # id. Those used to be skipped, so reordering the Update form, which is
  # almost all code defaults, saved nothing and still said it had.
  test "reorder positions default system fields by materializing them" do
    workspace = workspaces(:slack_workspace_one)
    form = workspace.ensure_incident_form!(IncidentForm::SLUG_UPDATE)
    resolver = IncidentFormResolver.new(workspace)

    before = resolver.resolve(IncidentForm::SLUG_UPDATE, include_hidden: true)
    ids = before.map { |field| field.id || "#{IncidentFormField::SYNTHETIC_PREFIX}#{field.system_field_key}" }
    assert ids.any? { |id| id.start_with?(IncidentFormField::SYNTHETIC_PREFIX) },
           "expected the update form to carry code defaults"

    IncidentFormService.new(workspace).reorder(form, ids.reverse)

    after = IncidentFormResolver.new(workspace).resolve(IncidentForm::SLUG_UPDATE, include_hidden: true)
    assert_equal keys_for(before).reverse, keys_for(after)
  end

  test "reorder refuses an id the form does not recognize" do
    workspace = workspaces(:slack_workspace_one)
    form = workspace.ensure_incident_form!(IncidentForm::SLUG_UPDATE)

    assert_raises(ActiveRecord::RecordNotFound) do
      IncidentFormService.new(workspace).reorder(form, [ SecureRandom.uuid ])
    end
  end

  private

  def keys_for(fields)
    fields.map { |field| field.system_field_key || field.incident_field_definition&.slug }
  end
end
