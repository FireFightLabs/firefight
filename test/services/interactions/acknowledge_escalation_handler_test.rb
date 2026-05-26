require "test_helper"

class Interactions::AcknowledgeEscalationHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @escalated_to = workspace_memberships(:alice_workspace_one)
    @escalated_by = workspace_memberships(:bob_workspace_one)

    @escalation_event = @incident.incident_events.create!(
      event_type: IncidentEvent::INCIDENT_ESCALATED,
      user: @escalated_by,
      metadata: {
        escalated_to_platform_user_id: @escalated_to.platform_user_id
      }
    )
  end

  test "acknowledges escalation and posts incident message" do
    stub_post_message
    stub_update_message

    assert_difference "IncidentEvent.count", 1 do
      result = Interactions::AcknowledgeEscalationHandler.execute(build_interaction(@escalated_to.platform_user_id))
      assert_nil result
    end

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::ESCALATION_ACKNOWLEDGED)
    assert_equal @escalated_to.platform_user_id, event.metadata["acknowledged_by_platform_user_id"]
    assert_equal @escalated_to.platform_user_id, @escalation_event.reload.metadata["acknowledged_by_platform_user_id"]
  end

  test "ignores acknowledgement from different user" do
    result = Interactions::AcknowledgeEscalationHandler.execute(build_interaction("U_NOT_TARGET"))

    assert_nil result
    assert_nil @incident.incident_events.find_by(event_type: IncidentEvent::ESCALATION_ACKNOWLEDGED)
  end

  private

  def build_interaction(user_id)
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::BLOCK_ACTIONS,
      team_id: @workspace.platform_id,
      channel_id: user_id,
      user_id: user_id,
      action_id: Identifiers::ACKNOWLEDGE_ESCALATION,
      action_value: {
        incident_id: @incident.id,
        escalation_event_id: @escalation_event.id
      }.to_json,
      raw: {
        "container" => {
          "channel_id" => user_id,
          "message_ts" => "1234567890.123456"
        }
      }
    )
  end
end
