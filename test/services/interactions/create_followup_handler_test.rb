require "test_helper"

class Interactions::CreateFollowupHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_severities, :incident_statuses

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @severity = incident_severities(:critical_ws1)
    @status = incident_statuses(:investigating_ws1)

    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: @status,
      incident_severity: @severity,
      name: "Test incident",
      is_private: false,
      channel_id: "C_TEST_INCIDENT"
    )
  end

  test "creates followup from modal submission" do
    stub_post_message

    result = Interactions::CreateFollowupHandler.execute(build_interaction(description: "Add monitoring"))

    assert_equal "clear", result[:response_action]
    action = @incident.incident_actions.find_by!(description: "Add monitoring")
    assert_equal "followup", action.action_type
    assert_equal @member, action.created_by
  end

  test "creates incident event for followup" do
    stub_post_message

    assert_difference -> { @incident.incident_events.count }, 1 do
      Interactions::CreateFollowupHandler.execute(build_interaction(description: "Write docs"))
    end

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::ACTION_CREATED)
    assert_equal "followup", event.metadata["action_type"]
  end

  private

  def build_interaction(description:)
    metadata = { incident_id: @incident.id }.to_json

    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_SUBMISSION,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      callback_id: Identifiers::CREATE_FOLLOWUP_MODAL,
      private_metadata: metadata,
      values: {
        "description_block" => {
          "description_input" => { "value" => description }
        },
        "assignee_block" => {
          "assignee_select" => { "selected_user" => nil }
        }
      }
    )
  end
end
