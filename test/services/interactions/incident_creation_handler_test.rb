require "test_helper"

class Interactions::IncidentCreationHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_severities,
           :incident_lifecycle_stages, :incident_statuses,
           :incident_forms, :incident_form_fields, :incident_field_definitions,
           :catalog_types, :catalog_entries

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
  end

  test "creates incident and returns confirmation modal" do
    stub_create_channel

    IncidentCreationWorkflow.expects(:start!).with do |incident|
      incident.name == "DB Down" && incident.workspace == @workspace
    end.once

    result = nil
    assert_difference "Incident.count", 1 do
      result = Interactions::IncidentCreationHandler.execute(
        build_interaction(severity: "critical", name: "DB Down", summary: nil, visibility: "public")
      )
    end

    assert_equal "update", result[:response_action]
    assert_equal "Incident declared", result[:view][:title][:text]

    incident = Incident.find_by!(name: "DB Down")
    assert_equal @workspace, incident.workspace
    assert_equal @member, incident.declared_by
    assert_equal "critical", incident.incident_severity.slug
    assert_equal "investigating", incident.incident_status.slug
    assert_equal false, incident.is_private
    assert_equal "C12345678", incident.channel_id
  end

  test "confirmation modal contains channel deep link" do
    stub_create_channel

    IncidentCreationWorkflow.stubs(:start!)

    result = Interactions::IncidentCreationHandler.execute(
      build_interaction(name: "Link Test")
    )

    actions = result[:view][:blocks].find { |b| b[:type] == "actions" }
    button = actions[:elements].first
    assert_equal "slack://channel?team=#{@workspace.platform_id}&id=C12345678", button[:url]
    assert_includes button[:text][:text], "Join incident channel"
  end

  # Visibility ships off, so a workspace that wants private incidents turns it
  # on first. The capability is unchanged, only the default.
  test "sets is_private when visibility is private" do
    stub_create_channel
    enable_visibility_field!

    IncidentCreationWorkflow.stubs(:start!)

    Interactions::IncidentCreationHandler.execute(
      build_interaction(visibility: "private")
    )

    incident = Incident.find_by!(name: "Test Incident")
    assert incident.is_private
  end

  def enable_visibility_field!
    form = @workspace.ensure_incident_form!(IncidentForm::SLUG_DECLARE)
    service = IncidentFormService.new(@workspace)
    row = service.ensure_system_field!(form, IncidentSystemField::KEY_VISIBILITY)
    service.update_field(row,
      visibility_mode: IncidentFormField::VISIBILITY_MODE_VISIBLE,
      required_mode: IncidentFormField::REQUIRED_MODE_OPTIONAL)
  end

  test "returns error for invalid severity" do
    result = Interactions::IncidentCreationHandler.execute(
      build_interaction(severity: "nonexistent")
    )

    assert_equal "errors", result[:response_action]
    assert result[:errors][:field_severity_block].present?
  end

  test "returns error for unknown workspace member" do
    result = Interactions::IncidentCreationHandler.execute(
      build_interaction(user_id: "U_UNKNOWN")
    )

    assert_equal "errors", result[:response_action]
  end

  test "creates incident with custom fields from form" do
    stub_create_channel
    IncidentCreationWorkflow.stubs(:start!)

    entry = catalog_entries(:auth_service)

    result = Interactions::IncidentCreationHandler.execute(
      build_interaction(
        severity: "critical",
        name: "Service Down",
        custom_fields: { "affected_services" => [ entry.id ] }
      )
    )

    assert_equal "update", result[:response_action]

    incident = Incident.find_by!(name: "Service Down")
    assert_equal [ entry.id ], incident.custom_fields["affected_services"]
  end

  private

  def build_interaction(severity: "minor", name: "Test Incident", summary: nil, visibility: "public", user_id: @member.platform_user_id, custom_fields: {})
    values = {
      "field_name_block" => { "field_name_input" => { "value" => name } },
      "field_severity_block" => { Identifiers::INCIDENT_CREATION_SEVERITY_SELECT => { "selected_option" => { "value" => severity } } },
      "field_visibility_block" => { "field_visibility_input" => { "selected_option" => { "value" => visibility } } }
    }

    custom_fields.each do |key, value|
      defn = @workspace.incident_field_definitions.find_by!(slug: key)
      block_id = "field_#{key}_block"
      action_id = "field_#{key}_input"

      if value.is_a?(Array)
        values[block_id] = { action_id => { "selected_options" => value.map { |v| { "value" => v } } } }
      elsif defn.field_type.in?([ IncidentFieldDefinition::TYPE_SINGLE_SELECT, IncidentFieldDefinition::TYPE_CATALOG_REFERENCE ])
        values[block_id] = { action_id => { "selected_option" => { "value" => value } } }
      else
        values[block_id] = { action_id => { "value" => value } }
      end
    end

    Interaction.new(
      platform: Platforms::SLACK,
      type: "view_submission",
      team_id: @workspace.platform_id,
      user_id: user_id,
      callback_id: Identifiers::INCIDENT_CREATION_MODAL,
      values: values
    )
  end
end
