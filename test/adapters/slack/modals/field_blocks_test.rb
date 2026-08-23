require "test_helper"

class Slack::Modals::FieldBlocksTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities, :incident_types, :incidents,
           :incident_forms, :incident_form_fields, :incident_field_definitions, :catalog_types

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "ids are the wire format every builder, parser and error anchor agrees on" do
    assert_equal "field_severity_block", Slack::Modals::FieldBlocks.block_id(IncidentSystemField::KEY_SEVERITY)
    assert_equal "field_severity_input", Slack::Modals::FieldBlocks.input_id(IncidentSystemField::KEY_SEVERITY)
    assert_equal "field_my_custom_block", Slack::Modals::FieldBlocks.block_id("my_custom")
  end

  test "a dispatching select carries its named action id, anything else its input id" do
    key = IncidentSystemField::KEY_STATUS

    assert_equal Identifiers::INCIDENT_UPDATE_STATUS_SELECT, Slack::Modals::FieldBlocks.action_id(key, dispatching: [ key ])
    assert_equal "field_status_input", Slack::Modals::FieldBlocks.action_id(key)
  end

  test "picked reads a dispatching select off the view state and survives an empty state" do
    state = { "field_severity_block" => { Identifiers::INCIDENT_CREATION_SEVERITY_SELECT => { "selected_option" => { "value" => "major" } } } }

    assert_equal "major", Slack::Modals::FieldBlocks.picked(state, IncidentSystemField::KEY_SEVERITY)
    assert_nil Slack::Modals::FieldBlocks.picked({}, IncidentSystemField::KEY_SEVERITY)
    assert_nil Slack::Modals::FieldBlocks.picked(nil, IncidentSystemField::KEY_SEVERITY)
  end

  test "build_system renders the picked option and dispatch only for the keys named" do
    severity_field = system_field(IncidentSystemField::KEY_SEVERITY)
    type_field = system_field(IncidentSystemField::KEY_INCIDENT_TYPE)
    type = @workspace.incident_types.active.first

    severity = Slack::Modals::FieldBlocks.build_system(
      @workspace, severity_field,
      dispatching: [ IncidentSystemField::KEY_SEVERITY ],
      selected: { IncidentSystemField::KEY_SEVERITY => "major" }
    )
    assert severity[:dispatch_action]
    assert_equal "major", severity.dig(:element, :initial_option, :value)

    type_block = Slack::Modals::FieldBlocks.build_system(
      @workspace, type_field,
      selected: { IncidentSystemField::KEY_INCIDENT_TYPE => type.slug }
    )
    assert_nil type_block[:dispatch_action]
    assert_equal "field_incident_type_input", type_block.dig(:element, :action_id)
    assert_equal type.slug, type_block.dig(:element, :initial_option, :value)
  end

  private

  def system_field(key)
    IncidentFormField.new(
      field_source_kind: IncidentFormField::FIELD_SOURCE_KIND_SYSTEM,
      system_field_key: key,
      required_mode: IncidentFormField::REQUIRED_MODE_OPTIONAL,
      visibility_mode: IncidentFormField::VISIBILITY_MODE_VISIBLE,
      position: 0
    )
  end
end
