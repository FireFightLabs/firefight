require "test_helper"

class Interactions::UpdateSummaryHandlerTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:alice_workspace_one)
  end

  test "updates incident summary and closes modal" do
    stub_all_side_effects

    result = Interactions::UpdateSummaryHandler.execute(
      build_interaction(summary: "New summary text")
    )

    assert_nil result
    assert_equal "New summary text", @incident.reload.summary
  end

  test "creates incident event with incident update" do
    stub_all_side_effects

    assert_difference -> { @incident.incident_events.count }, 1 do
      Interactions::UpdateSummaryHandler.execute(
        build_interaction(summary: "Updated summary")
      )
    end

    event = @incident.incident_events.updates.find_by!(event_type: IncidentEvent::INCIDENT_UPDATED)
    assert_equal @member, event.actor
    assert_instance_of IncidentUpdate, event.eventable
    assert event.changed?(:summary)
  end

  test "starts summary update workflow" do
    stub_all_side_effects

    assert_difference "SolidWorkflow::Workflow.count", 1 do
      Interactions::UpdateSummaryHandler.execute(
        build_interaction(summary: "Updated summary")
      )
    end

    workflow = SolidWorkflow::Workflow.find_by!(name: "incident.summary_update.v1", subject: @incident)
    assert_equal @member.platform_user_id, workflow.context["updated_by_platform_user_id"]
  end

  test "returns modal error when incident not found" do
    stub_delete_message

    interaction = Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_SUBMISSION,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      callback_id: Identifiers::UPDATE_SUMMARY_MODAL,
      private_metadata: { incident_id: SecureRandom.uuid, temp_message_ts: "1234567890.123456", channel_id: "C12345678" }.to_json,
      values: { "summary_block" => { "summary_input" => { "value" => "test" } } }
    )

    result = Interactions::UpdateSummaryHandler.execute(interaction)

    assert_equal "errors", result[:response_action]
    assert result[:errors]["summary_block"].present?
  end

  private

  def build_interaction(summary: "New summary")
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_SUBMISSION,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      callback_id: Identifiers::UPDATE_SUMMARY_MODAL,
      private_metadata: { incident_id: @incident.id, temp_message_ts: "1234567890.123456", channel_id: @incident.channel_id }.to_json,
      values: {
        "summary_block" => {
          "summary_input" => {
            "value" => summary
          }
        }
      }
    )
  end

  def stub_all_side_effects
    stub_update_message
    stub_post_message
    stub_delete_message
  end
end
