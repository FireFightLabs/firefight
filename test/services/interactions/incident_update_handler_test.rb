require "test_helper"

class Interactions::IncidentUpdateHandlerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities, :incident_types, :incident_roles,
           :incident_forms, :incident_form_fields, :catalog_types, :incident_field_definitions, :incident_field_options

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @workspace.update!(incidents_channel_id: "C_INCIDENTS")
    @member = workspace_memberships(:alice_workspace_one)
    @status = incident_statuses(:investigating_ws1)
    @severity = incident_severities(:critical_ws1)

    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: @status,
      incident_severity: @severity,
      name: "Test incident",
      is_private: false,
      channel_id: "C_TEST_INCIDENT",
      initial_message_ts: "1234567890.111111",
      announcement_message_ts: "1234567890.222222",
      source: Incident::SOURCE_SLACK
    )
  end

  test "updates incident status and severity" do
    stub_all_side_effects

    result = Interactions::IncidentUpdateHandler.execute(
      build_interaction(status_slug: "identified", severity_slug: "major")
    )

    assert_nil result
    @incident.reload
    assert_equal "identified", @incident.incident_status.slug
    assert_equal "major", @incident.incident_severity.slug
  end

  test "picking a closed status in the update modal closes the incident for real" do
    stub_all_side_effects
    closed = @workspace.incident_statuses.closed.active.first
    IncidentCloseWorkflow.expects(:start!).once
    IncidentUpdateWorkflow.expects(:start!).never

    Interactions::IncidentUpdateHandler.execute(build_interaction(status_slug: closed.slug))

    @incident.reload
    assert_equal closed, @incident.incident_status
    assert @incident.resolved_at.present?
    assert @incident.incident_events.exists?(event_type: IncidentEvent::INCIDENT_RESOLVED)
    assert_not @incident.incident_events.exists?(event_type: IncidentEvent::INCIDENT_UPDATED)
  end

  test "creates incident event with change tracking" do
    stub_all_side_effects

    assert_difference [ "IncidentEvent.count", "IncidentUpdate.count" ], 1 do
      Interactions::IncidentUpdateHandler.execute(
        build_interaction(status_slug: "identified", severity_slug: "major")
      )
    end

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::INCIDENT_UPDATED)
    assert_equal @member, event.actor
    assert_instance_of IncidentUpdate, event.eventable
    assert event.changed?(:status)
    assert event.changed?(:severity)
  end

  test "starts incident update workflow with context" do
    stub_all_side_effects

    assert_difference "SolidWorkflow::Workflow.count", 1 do
      Interactions::IncidentUpdateHandler.execute(
        build_interaction(status_slug: "identified", severity_slug: "major", message: "Working on fix")
      )
    end

    workflow = SolidWorkflow::Workflow.find_by!(name: "incident.incident_update.v1", subject: @incident)
    assert_equal @member.platform_user_id, workflow.context["updated_by_platform_user_id"]
    assert_equal "Working on fix", workflow.context["message"]
    assert_equal "Investigating", workflow.context["previous_status_name"]
    assert_equal "Critical", workflow.context["previous_severity_name"]
  end

  test "sets incident type" do
    stub_all_side_effects

    Interactions::IncidentUpdateHandler.execute(
      build_interaction(type_slug: "service_outage")
    )

    @incident.reload
    assert_equal "service_outage", @incident.incident_type.slug
  end

  test "clears incident type when none selected" do
    @incident.update!(incident_type: incident_types(:service_outage_ws1))
    stub_all_side_effects

    Interactions::IncidentUpdateHandler.execute(
      build_interaction(type_slug: nil)
    )

    assert_nil @incident.reload.incident_type
  end

  test "type change appears in changed_fields" do
    stub_all_side_effects

    Interactions::IncidentUpdateHandler.execute(
      build_interaction(type_slug: "service_outage")
    )

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::INCIDENT_UPDATED)
    assert event.changed?(:type)
  end

  test "workflow context includes previous_type_name" do
    @incident.update!(incident_type: incident_types(:service_outage_ws1))
    stub_all_side_effects

    Interactions::IncidentUpdateHandler.execute(
      build_interaction(type_slug: "performance_degradation")
    )

    workflow = SolidWorkflow::Workflow.find_by!(name: "incident.incident_update.v1", subject: @incident)
    assert_equal "Service Outage", workflow.context["previous_type_name"]
  end

  test "sets next_update_at when timer selected" do
    stub_all_side_effects

    freeze_time do
      Interactions::IncidentUpdateHandler.execute(
        build_interaction(next_update_minutes: "30")
      )

      @incident.reload
      assert_equal 30.minutes.from_now.to_i, @incident.next_update_at.to_i
    end
  end

  test "clears next_update_at when no timer selected" do
    @incident.update!(next_update_at: 30.minutes.from_now)
    stub_all_side_effects

    Interactions::IncidentUpdateHandler.execute(
      build_interaction
    )

    assert_nil @incident.reload.next_update_at
  end

  test "schedules reminder job when timer selected" do
    stub_all_side_effects

    assert_enqueued_with(job: IncidentUpdateReminderJob) do
      Interactions::IncidentUpdateHandler.execute(
        build_interaction(next_update_minutes: "30")
      )
    end
  end

  # The modal drops the timer as soon as a closing status is picked, but a
  # submission from a view that never got that refresh still carries one. It
  # has to submit cleanly rather than fail on a field the form no longer asks.
  test "clears next_update_at when the status closes the incident" do
    stub_all_side_effects

    result = Interactions::IncidentUpdateHandler.execute(
      build_interaction(status_slug: "resolved", next_update_minutes: "30")
    )

    assert_nil result
    assert_nil @incident.reload.next_update_at
  end

  test "clears next_update_at when the status cancels the incident" do
    stub_all_side_effects

    Interactions::IncidentUpdateHandler.execute(
      build_interaction(status_slug: "canceled", next_update_minutes: "30")
    )

    assert_nil @incident.reload.next_update_at
  end

  test "does not schedule a reminder when the status ends the incident" do
    stub_all_side_effects

    assert_no_enqueued_jobs only: IncidentUpdateReminderJob do
      Interactions::IncidentUpdateHandler.execute(
        build_interaction(status_slug: "resolved", next_update_minutes: "30")
      )
    end
  end

  test "snapshots the next_update_at the submission asked for" do
    stub_all_side_effects

    freeze_time do
      Interactions::IncidentUpdateHandler.execute(
        build_interaction(next_update_minutes: "30")
      )

      event = @incident.incident_events.find_by!(event_type: IncidentEvent::INCIDENT_UPDATED)
      assert_equal 30.minutes.from_now.to_i, event.eventable.next_update_at.to_i
    end
  end

  test "returns modal error when incident not found" do
    stub_delete_message

    interaction = Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_SUBMISSION,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      callback_id: Identifiers::INCIDENT_UPDATE_MODAL,
      private_metadata: { incident_id: SecureRandom.uuid, temp_message_ts: "1234567890.123456", channel_id: "C12345678" }.to_json,
      values: build_values
    )

    result = Interactions::IncidentUpdateHandler.execute(interaction)

    assert_equal "errors", result[:response_action]
    assert result[:errors]["field_status_block"].present?
  end

  test "saves custom fields from form" do
    stub_all_side_effects
    option = incident_field_options(:customer_tier_enterprise)

    Interactions::IncidentUpdateHandler.execute(
      build_interaction(custom_fields: { "customer_tier" => option.id })
    )

    @incident.reload
    assert_equal option.id, @incident.custom_fields["customer_tier"]
    assert_equal "Enterprise", @incident.custom_fields_for_display["customer_tier"]
  end

  test "leaves fields the form did not submit untouched" do
    notes = notes_definition
    @incident.update!(custom_fields: { notes.slug => "existing_value" })
    stub_all_side_effects

    Interactions::IncidentUpdateHandler.execute(
      build_interaction(custom_fields: { "customer_tier" => incident_field_options(:customer_tier_pro).id })
    )

    @incident.reload
    assert_equal "existing_value", @incident.custom_fields[notes.slug]
    assert_equal "Pro", @incident.custom_fields_for_display["customer_tier"]
  end

  private

  def notes_definition
    @workspace.incident_field_definitions.create!(
      slug: "root_cause_notes",
      name: "Root Cause Notes",
      field_type: IncidentFieldDefinition::TYPE_TEXT,
      option_source: IncidentFieldDefinition::OPTION_SOURCE_NONE,
      position: 99
    )
  end

  def build_interaction(status_slug: "investigating", severity_slug: "critical", type_slug: nil, message: "Still investigating.", next_update_minutes: nil, custom_fields: {})
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_SUBMISSION,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      callback_id: Identifiers::INCIDENT_UPDATE_MODAL,
      private_metadata: { incident_id: @incident.id, temp_message_ts: "1234567890.123456", channel_id: @incident.channel_id }.to_json,
      values: build_values(status_slug: status_slug, severity_slug: severity_slug, type_slug: type_slug, message: message, next_update_minutes: next_update_minutes, custom_fields: custom_fields)
    )
  end

  def build_values(status_slug: "investigating", severity_slug: "critical", type_slug: nil, message: "Still investigating.", next_update_minutes: nil, custom_fields: {})
    vals = {
      "field_status_block" => {
        "field_status_input" => {
          "selected_option" => { "value" => status_slug }
        }
      },
      "field_severity_block" => {
        "field_severity_input" => {
          "selected_option" => { "value" => severity_slug }
        }
      },
      "field_incident_type_block" => {
        "field_incident_type_input" => {
          "selected_option" => type_slug ? { "value" => type_slug } : nil
        }
      },
      "field_message_block" => {
        "field_message_input" => {
          "value" => message
        }
      },
      "field_next_update_block" => {
        "field_next_update_input" => {
          "selected_option" => next_update_minutes ? { "value" => next_update_minutes } : nil
        }
      }
    }

    custom_fields.each do |key, value|
      vals["field_#{key}_block"] = {
        "field_#{key}_input" => {
          "selected_option" => { "value" => value }
        }
      }
    end

    vals
  end

  def stub_all_side_effects
    stub_update_message
    stub_post_message
    stub_delete_message
    stub_set_channel_topic
    stub_set_channel_purpose
  end
end
