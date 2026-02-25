require "test_helper"

class Interactions::IncidentUpdateHandlerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_statuses, :incident_severities, :incident_roles

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
      announcement_message_ts: "1234567890.222222"
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

  test "creates incident event with change tracking" do
    stub_all_side_effects

    assert_difference [ "IncidentEvent.count", "IncidentUpdate.count" ], 1 do
      Interactions::IncidentUpdateHandler.execute(
        build_interaction(status_slug: "identified", severity_slug: "major")
      )
    end

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::INCIDENT_UPDATED)
    assert_equal @member, event.user
    assert_instance_of IncidentUpdate, event.eventable
    assert event.changed?(:status)
    assert event.changed?(:severity)
  end

  test "starts incident update workflow with context" do
    stub_all_side_effects

    assert_difference "Workflow.count", 1 do
      Interactions::IncidentUpdateHandler.execute(
        build_interaction(status_slug: "identified", severity_slug: "major", message: "Working on fix")
      )
    end

    workflow = Workflow.find_by!(name: "incident.incident_update.v1", subject: @incident)
    assert_equal @member.platform_user_id, workflow.context["updated_by_platform_user_id"]
    assert_equal "Working on fix", workflow.context["message"]
    assert_equal "Investigating", workflow.context["previous_status_name"]
    assert_equal "Critical", workflow.context["previous_severity_name"]
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
    assert result[:errors]["status_block"].present?
  end

  private

  def build_interaction(status_slug: "investigating", severity_slug: "critical", message: nil, next_update_minutes: nil)
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_SUBMISSION,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      callback_id: Identifiers::INCIDENT_UPDATE_MODAL,
      private_metadata: { incident_id: @incident.id, temp_message_ts: "1234567890.123456", channel_id: @incident.channel_id }.to_json,
      values: build_values(status_slug: status_slug, severity_slug: severity_slug, message: message, next_update_minutes: next_update_minutes)
    )
  end

  def build_values(status_slug: "investigating", severity_slug: "critical", message: nil, next_update_minutes: nil)
    values = {
      "status_block" => {
        "status_select" => {
          "selected_option" => { "value" => status_slug }
        }
      },
      "severity_block" => {
        "severity_select" => {
          "selected_option" => { "value" => severity_slug }
        }
      },
      "message_block" => {
        "message_input" => {
          "value" => message
        }
      },
      "next_update_block" => {
        "next_update_select" => {
          "selected_option" => next_update_minutes ? { "value" => next_update_minutes } : nil
        }
      }
    }
    values
  end

  def stub_all_side_effects
    stub_update_message
    stub_post_message
    stub_delete_message
    stub_set_channel_topic
    stub_set_channel_purpose
  end
end
