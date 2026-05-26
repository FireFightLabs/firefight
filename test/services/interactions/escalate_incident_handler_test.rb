require "test_helper"

class Interactions::EscalateIncidentHandlerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  fixtures :workspaces, :users, :workspace_memberships,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities, :incident_roles

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @workspace.update!(incidents_channel_id: "C_INCIDENTS")
    @member = workspace_memberships(:alice_workspace_one)
    @target = workspace_memberships(:bob_workspace_one)
    @status = incident_statuses(:investigating_ws1)
    @severity = incident_severities(:critical_ws1)

    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: @status,
      incident_severity: @severity,
      name: "Test incident",
      summary: "Something is broken",
      is_private: false,
      channel_id: "C_TEST_INCIDENT",
      initial_message_ts: "1234567890.111111",
      announcement_message_ts: "1234567890.222222",
      source: Incident::SOURCE_SLACK
    )
  end

  test "creates incident escalated event" do
    stub_post_message
    stub_delete_message

    assert_difference "IncidentEvent.count", 1 do
      Interactions::EscalateIncidentHandler.execute(build_interaction)
    end

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::INCIDENT_ESCALATED)
    assert_equal @member, event.user
    assert_equal @target.platform_user_id, event.metadata["escalated_to_platform_user_id"]
    assert_equal "Need backend support", event.metadata["reason"]
  end

  test "starts incident escalation workflow" do
    stub_post_message
    stub_delete_message

    assert_difference "SolidWorkflow::Workflow.count", 1 do
      Interactions::EscalateIncidentHandler.execute(build_interaction)
    end

    workflow = SolidWorkflow::Workflow.find_by!(name: "incident.escalation.v1", subject: @incident)
    assert_equal @member.platform_user_id, workflow.context["escalated_by_platform_user_id"]
    assert_equal @target.platform_user_id, workflow.context["escalated_to_platform_user_id"]
    assert_equal "Need backend support", workflow.context["reason"]
    assert_not_nil workflow.context["escalation_event_id"]
  end

  test "enqueues acknowledgement reminder" do
    stub_post_message
    stub_delete_message

    assert_enqueued_with(job: EscalationAcknowledgementReminderJob, queue: "events") do
      Interactions::EscalateIncidentHandler.execute(build_interaction)
    end
  end

  test "cleans up temp message on success" do
    stub_post_message
    Slack::Client.expects(:delete_message).once.returns({ ok: true, ts: "1234567890.123456", channel: "C12345678" })

    Interactions::EscalateIncidentHandler.execute(build_interaction)
  end

  test "returns error when incident not found" do
    stub_delete_message

    interaction = Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_SUBMISSION,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      callback_id: Identifiers::ESCALATE_INCIDENT_MODAL,
      private_metadata: { incident_id: SecureRandom.uuid, temp_message_ts: "1234567890.123456", channel_id: "C12345678" }.to_json,
      values: build_values
    )

    result = Interactions::EscalateIncidentHandler.execute(interaction)

    assert_equal "errors", result[:response_action]
  end

  private

  def build_interaction(reason: "Need backend support")
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_SUBMISSION,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      callback_id: Identifiers::ESCALATE_INCIDENT_MODAL,
      private_metadata: { incident_id: @incident.id, temp_message_ts: "1234567890.123456", channel_id: @incident.channel_id }.to_json,
      values: build_values(reason: reason)
    )
  end

  def build_values(reason: "Need backend support")
    {
      "escalate_to_block" => {
        "escalate_to_select" => { "selected_user" => @target.platform_user_id }
      },
      "reason_block" => {
        "reason_input" => { "value" => reason }
      }
    }
  end
end
