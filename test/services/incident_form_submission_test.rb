require "test_helper"

class IncidentFormSubmissionTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships,
           :incident_severities, :incident_types,
           :incident_lifecycle_stages, :incident_statuses,
           :incident_forms, :incident_form_fields, :incident_field_definitions,
           :catalog_types, :catalog_entries, :incidents

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "parses a valid declare submission with system fields only" do
    values = {
      "field_name_block" => { "field_name_input" => { "value" => "DB down" } },
      "field_severity_block" => {
        "incident_creation_severity_select" => { "selected_option" => { "value" => "critical" } }
      }
    }

    result = IncidentFormSubmission.new(
      workspace: @workspace, form_slug: IncidentForm::SLUG_DECLARE, values: values
    ).parse

    assert_empty result.errors
    assert_equal({ "name" => "DB down", "severity" => "critical" }, result.system_attrs)
    assert_empty result.custom_fields
  end

  test "reads severity regardless of which action_id the modal builder used" do
    # The declare modal builder uses the dispatch action_id
    # (`incident_creation_severity_select`). The submission parser must not
    # require knowing that name — it should accept whatever action key sits
    # under the severity block.
    values = {
      "field_severity_block" => {
        "some_other_action_id" => { "selected_option" => { "value" => "major" } }
      }
    }

    result = IncidentFormSubmission.new(
      workspace: @workspace, form_slug: IncidentForm::SLUG_DECLARE, values: values
    ).parse

    assert_equal "major", result.system_attrs["severity"]
  end

  test "extracts a custom catalog_multi_reference field as an array of entry IDs" do
    entry = catalog_entries(:auth_service)

    values = {
      "field_severity_block" => {
        "incident_creation_severity_select" => { "selected_option" => { "value" => "critical" } }
      },
      "field_affected_services_block" => {
        "field_affected_services_input" => {
          "selected_options" => [ { "value" => entry.id } ]
        }
      }
    }

    result = IncidentFormSubmission.new(
      workspace: @workspace, form_slug: IncidentForm::SLUG_DECLARE, values: values
    ).parse

    assert_empty result.errors
    assert_equal({ "affected_services" => [ entry.id ] }, result.custom_fields)
  end

  test "returns errors and first_error_block_id when a fixed-required field is missing" do
    values = {
      "field_name_block" => { "field_name_input" => { "value" => "No severity" } }
    }

    result = IncidentFormSubmission.new(
      workspace: @workspace, form_slug: IncidentForm::SLUG_DECLARE, values: values
    ).parse

    refute_empty result.errors
    assert_match(/Severity is required/i, result.errors.first)
    assert_equal "field_name_block", result.first_error_block_id
  end

  test "parses an update submission with incident context falling back to current values" do
    # No severity slug in the submission — context should fall back to the
    # existing incident's severity so condition evaluation still works.
    values = {
      "field_status_block" => {
        "field_status_input" => { "selected_option" => { "value" => "monitoring" } }
      },
      "field_severity_block" => {
        "field_severity_input" => { "selected_option" => { "value" => @incident.incident_severity.slug } }
      }
    }

    result = IncidentFormSubmission.new(
      workspace: @workspace,
      form_slug: IncidentForm::SLUG_UPDATE,
      values: values,
      incident: @incident
    ).parse

    assert_empty result.errors
    assert_equal "monitoring", result.system_attrs["status"]
    assert_equal @incident.incident_severity.slug, result.system_attrs["severity"]
  end

  test "falls back to code defaults when no IncidentForm DB row exists" do
    @workspace.incident_forms.where(lifecycle_event: IncidentForm::SLUG_DECLARE).destroy_all

    values = {
      "field_severity_block" => {
        "field_severity_input" => { "selected_option" => { "value" => "critical" } }
      }
    }
    result = IncidentFormSubmission.new(
      workspace: @workspace, form_slug: IncidentForm::SLUG_DECLARE, values: values
    ).parse

    assert_empty result.errors
    assert_equal "critical", result.system_attrs["severity"]
  end

  test "code-default system fields apply when no DB overlay rows exist" do
    # Strip every overlay row from the declare form — defaults still apply.
    form = @workspace.incident_forms.find_by!(lifecycle_event: IncidentForm::SLUG_DECLARE)
    form.incident_form_fields.destroy_all

    values = {
      "field_severity_block" => {
        "field_severity_input" => { "selected_option" => { "value" => "critical" } }
      }
    }
    result = IncidentFormSubmission.new(
      workspace: @workspace, form_slug: IncidentForm::SLUG_DECLARE, values: values
    ).parse

    assert_empty result.errors
    # Defaults include name + severity + summary + incident_type + visibility on declare.
    assert result.includes_system_key?(IncidentSystemField::KEY_SEVERITY)
    assert result.includes_system_key?(IncidentSystemField::KEY_VISIBILITY)
  end

  test "exposes visible_system_keys for callers that need to distinguish 'on form' from 'absent value'" do
    values = {
      "field_severity_block" => {
        "incident_creation_severity_select" => { "selected_option" => { "value" => "critical" } }
      }
    }

    result = IncidentFormSubmission.new(
      workspace: @workspace, form_slug: IncidentForm::SLUG_DECLARE, values: values
    ).parse

    assert result.includes_system_key?(IncidentSystemField::KEY_NAME)
    assert result.includes_system_key?(IncidentSystemField::KEY_SEVERITY)
    refute result.includes_system_key?(IncidentSystemField::KEY_STATUS)
  end

  test "ignores blocks not in the resolved field list" do
    values = {
      "field_severity_block" => {
        "incident_creation_severity_select" => { "selected_option" => { "value" => "critical" } }
      },
      "field_unknown_block" => { "field_unknown_input" => { "value" => "ignored" } }
    }

    result = IncidentFormSubmission.new(
      workspace: @workspace, form_slug: IncidentForm::SLUG_DECLARE, values: values
    ).parse

    assert_empty result.errors
    refute_includes result.system_attrs.keys, "unknown"
    refute_includes result.custom_fields.keys, "unknown"
  end
end
