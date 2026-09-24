require "test_helper"

class Interactions::IncidentCreationHandlerTest < ActiveSupport::TestCase
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

  test "an incident declared from an answer carries the run that offered it, on its timeline" do
    stub_create_channel
    IncidentCreationWorkflow.stubs(:start!)
    run = question_run
    run.conclude!(summary: "Checkout writes time out on the orders database", suggest_incident: true)

    Interactions::IncidentCreationHandler.execute(
      build_interaction(name: "Checkout is slow", private_metadata: ModalState.encode(investigation_id: run.id))
    )

    incident = @workspace.incidents.find_by!(name: "Checkout is slow")
    assert_equal incident, run.reload.subject
    assert_equal [ IncidentEvent::INVESTIGATION_STARTED, IncidentEvent::INVESTIGATION_ANSWERED ],
                 incident.incident_events.where(event_type: IncidentEvent::INVESTIGATION_EVENTS).order(:created_at).pluck(:event_type)
  end

  test "the declare button on an answer opens the declare form holding the run" do
    run = question_run
    Slack::Client.expects(:open_modal).with do |arguments|
      ModalState.parse(arguments[:view][:private_metadata]).investigation_id == run.id
    end.returns({ ok: true })

    Interactions::DeclareFromInvestigationHandler.execute(
      Interaction.new(
        platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id, user_id: @member.platform_user_id,
        action_id: Identifiers::DECLARE_INCIDENT_FROM_INVESTIGATION, action_value: run.id, trigger_id: "trigger"
      )
    )
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

  # Visibility ships off, a workspace that wants private incidents turns it on first.
  test "a modal opened for a test incident creates one" do
    stub_successful_slack_workflow
    attrs = build_interaction(name: "Onboarding run").resume_attrs.merge(private_metadata: ModalState.encode(test: true))

    Interactions::IncidentCreationHandler.execute(Interaction.new(attrs))

    assert @workspace.incidents.find_by!(name: "Onboarding run").is_test?
    assert_not @workspace.incidents.find_by!(name: "Onboarding run", is_test: true).nil?
  end

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

  test "returns an account error rather than a severity error for an unknown workspace member" do
    result = Interactions::IncidentCreationHandler.execute(
      build_interaction(user_id: "U_UNKNOWN")
    )

    assert_equal "errors", result[:response_action]
    assert_not result[:errors].key?(Slack::Modals::FieldBlocks.block_id(IncidentSystemField::KEY_SEVERITY))
    assert_includes result[:errors][Slack::Modals::FieldBlocks.block_id(IncidentSystemField::KEY_NAME)], "verify your account"
  end

  test "returns a severity error when the member is known and the severity is not" do
    result = Interactions::IncidentCreationHandler.execute(
      build_interaction(severity: "nonexistent")
    )

    assert_equal "errors", result[:response_action]
    assert_not result[:errors].key?(Slack::Modals::FieldBlocks.block_id(IncidentSystemField::KEY_NAME))
    assert_includes result[:errors][Slack::Modals::FieldBlocks.block_id(IncidentSystemField::KEY_SEVERITY)], "Invalid severity selection"
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

  def question_run
    @workspace.investigations.create!(
      trigger_source: Investigation::TRIGGER_COMMAND, triggered_by: @member, max_turns: 10, max_spend_cents: 400,
      status: Investigation::STATUS_SUCCEEDED, brief: { Investigation::Brief::KEY_SYMPTOM => "checkout is slow" }
    )
  end

  def build_interaction(severity: "minor", name: "Test Incident", summary: nil, visibility: "public", user_id: @member.platform_user_id, custom_fields: {}, private_metadata: nil)
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
      values: values,
      private_metadata: private_metadata
    )
  end
end
