require "test_helper"

class Interactions::CreateActionItemHandlerTest < ActiveSupport::TestCase
  KINDS = {
    Identifiers::CREATE_ACTION_MODAL => IncidentAction::ACTION_TYPE_ACTION,
    Identifiers::CREATE_FOLLOWUP_MODAL => IncidentAction::ACTION_TYPE_FOLLOWUP
  }.freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)

    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: incident_statuses(:investigating_ws1),
      incident_severity: incident_severities(:critical_ws1),
      name: "Test incident",
      is_private: false,
      channel_id: "C_TEST_INCIDENT",
      source: Incident::SOURCE_SLACK
    )
  end

  test "the callback_id decides whether the submission is an action or a follow-up" do
    stub_post_message

    KINDS.each do |callback_id, action_type|
      result = Interactions::CreateActionItemHandler.execute(
        build_interaction(callback_id: callback_id, description: "Item for #{action_type}")
      )

      assert_equal "clear", result[:response_action]
      item = @incident.incident_actions.find_by!(description: "Item for #{action_type}")
      assert_equal action_type, item.action_type
      assert_nil item.assignee
      event = @incident.incident_events.find_by!(event_type: IncidentEvent::ACTION_CREATED, eventable: item.incident_action_updates)
      assert_equal @member, event.actor
      assert_equal IncidentActionUpdate::CREATED, event.eventable.update_type
    end
  end

  test "creates with an assignee" do
    stub_post_message

    result = Interactions::CreateActionItemHandler.execute(
      build_interaction(callback_id: Identifiers::CREATE_ACTION_MODAL, description: "Check logs", assignee_user_id: @bob.platform_user_id)
    )

    assert_equal "clear", result[:response_action]
    assert_equal @bob, @incident.incident_actions.find_by!(description: "Check logs").assignee
  end

  test "keeps the link to the message a reaction started from" do
    stub_post_message
    metadata = Slack::PrivateMetadata.encode(
      incident_id: @incident.id, source_message_text: "Original message", source_message_link: "https://example.com/msg"
    )

    Interactions::CreateActionItemHandler.execute(
      build_interaction(callback_id: Identifiers::CREATE_FOLLOWUP_MODAL, description: "From reaction", private_metadata: metadata)
    )

    item = @incident.incident_actions.find_by!(description: "From reaction")
    assert_equal "https://example.com/msg", item.platform_data["source_message_link"]
    assert_equal IncidentAction::ACTION_TYPE_FOLLOWUP, item.action_type
  end

  test "returns a modal error when the incident is gone" do
    metadata = Slack::PrivateMetadata.encode(incident_id: SecureRandom.uuid)

    result = Interactions::CreateActionItemHandler.execute(
      build_interaction(callback_id: Identifiers::CREATE_ACTION_MODAL, description: "Test", private_metadata: metadata)
    )

    assert_equal "errors", result[:response_action]
  end

  private

  def build_interaction(callback_id:, description:, assignee_user_id: nil, private_metadata: nil)
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_SUBMISSION,
      team_id: @workspace.platform_id,
      user_id: @member.platform_user_id,
      callback_id: callback_id,
      private_metadata: private_metadata || Slack::PrivateMetadata.encode(incident_id: @incident.id),
      values: {
        "description_block" => { "description_input" => { "value" => description } },
        "assignee_block" => { "assignee_select" => { "selected_user" => assignee_user_id } }
      }
    )
  end
end
