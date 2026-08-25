require "test_helper"

class EscalationAcknowledgementReminderJobTest < ActiveJob::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @escalated_by = workspace_memberships(:bob_workspace_one)
    @escalated_to = workspace_memberships(:alice_workspace_one)

    @escalation_event = @incident.incident_events.create!(
      event_type: IncidentEvent::INCIDENT_ESCALATED,
      actor: @escalated_by,
      metadata: {
        escalated_to_platform_user_id: @escalated_to.platform_user_id,
        escalated_to_member_id: @escalated_to.id,
        escalated_to_name: @escalated_to.display_name
      }
    )
  end

  test "sends reminder when escalation is not acknowledged" do
    stub_post_message

    assert_difference "IncidentEvent.count", 1 do
      EscalationAcknowledgementReminderJob.perform_now(
        @incident.id,
        @escalation_event.id,
        @escalated_by.platform_user_id,
        @escalated_to.platform_user_id,
        "please help"
      )
    end

    nudge_event = @incident.incident_events.find_by!(event_type: IncidentEvent::ESCALATION_NUDGED)
    assert_equal @escalated_to.platform_user_id, nudge_event.metadata["escalated_to_platform_user_id"]
    assert_equal @escalated_to.id, nudge_event.metadata["escalated_to_member_id"]
    assert_equal @escalated_to.display_name, nudge_event.metadata["escalated_to_name"]
  end

  test "does not send reminder when already acknowledged" do
    @escalation_event.update!(
      metadata: {
        escalated_to_platform_user_id: @escalated_to.platform_user_id,
        acknowledged_by_platform_user_id: @escalated_to.platform_user_id
      }
    )

    assert_no_difference "IncidentEvent.count" do
      EscalationAcknowledgementReminderJob.perform_now(
        @incident.id,
        @escalation_event.id,
        @escalated_by.platform_user_id,
        @escalated_to.platform_user_id
      )
    end
  end
end
