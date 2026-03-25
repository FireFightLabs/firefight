require "test_helper"

class Interactions::CreateActionHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_severities, :incident_lifecycle_stages, :incident_statuses

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @severity = incident_severities(:critical_ws1)
    @status = incident_statuses(:investigating_ws1)

    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: @status,
      incident_severity: @severity,
      name: "Test incident",
      is_private: false,
      channel_id: "C_TEST_INCIDENT",
      source: Incident::SOURCE_SLACK
    )
  end

  test "creates action from modal submission" do
    stub_post_message

    result = Interactions::CreateActionHandler.execute(build_interaction(description: "Restart the service"))

    assert_equal "clear", result[:response_action]
    action = @incident.incident_actions.find_by!(description: "Restart the service")
    assert_equal "action", action.action_type
    assert_equal @member, action.created_by
    assert_nil action.assignee
  end

  test "creates action with assignee" do
    stub_post_message

    result = Interactions::CreateActionHandler.execute(
      build_interaction(description: "Check logs", assignee_user_id: @bob.platform_user_id)
    )

    assert_equal "clear", result[:response_action]
    action = @incident.incident_actions.find_by!(description: "Check logs")
    assert_equal @bob, action.assignee
  end

  test "creates incident event with action update" do
    stub_post_message

    assert_difference [ "IncidentEvent.count", "IncidentActionUpdate.count" ], 1 do
      Interactions::CreateActionHandler.execute(build_interaction(description: "Fix it"))
    end

    event = @incident.incident_events.find_by!(event_type: IncidentEvent::ACTION_CREATED)
    assert_equal @member, event.user
    assert_instance_of IncidentActionUpdate, event.eventable
    assert_equal IncidentActionUpdate::CREATED, event.eventable.update_type
  end

  test "stores platform_data from reaction source" do
    stub_post_message

    metadata = {
      incident_id: @incident.id,
      source_message_text: "Original message",
      source_message_link: "https://example.com/msg"
    }.to_json

    interaction = Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_SUBMISSION,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      callback_id: Identifiers::CREATE_ACTION_MODAL,
      private_metadata: metadata,
      values: build_values(description: "From reaction")
    )

    Interactions::CreateActionHandler.execute(interaction)

    action = @incident.incident_actions.find_by!(description: "From reaction")
    assert_equal "https://example.com/msg", action.platform_data["source_message_link"]
  end

  test "returns error when incident not found" do
    metadata = { incident_id: SecureRandom.uuid }.to_json

    interaction = Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_SUBMISSION,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      callback_id: Identifiers::CREATE_ACTION_MODAL,
      private_metadata: metadata,
      values: build_values(description: "Test")
    )

    result = Interactions::CreateActionHandler.execute(interaction)

    assert_equal "errors", result[:response_action]
  end

  private

  def build_interaction(description:, assignee_user_id: nil)
    metadata = { incident_id: @incident.id }.to_json

    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_SUBMISSION,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      callback_id: Identifiers::CREATE_ACTION_MODAL,
      private_metadata: metadata,
      values: build_values(description: description, assignee_user_id: assignee_user_id)
    )
  end

  def build_values(description:, assignee_user_id: nil)
    {
      "description_block" => {
        "description_input" => { "value" => description }
      },
      "assignee_block" => {
        "assignee_select" => { "selected_user" => assignee_user_id }
      }
    }
  end
end
