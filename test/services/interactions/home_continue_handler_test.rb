require "test_helper"

class Interactions::HomeContinueHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "replaces home modal with incident action modal" do
    Slack::Modals::IncidentUpdate.expects(:build).returns({ "type" => "modal", "title" => { "type" => "plain_text", "text" => "Update Incident" } })

    result = Interactions::HomeContinueHandler.execute(
      build_interaction(selected: Identifiers::HOME_ACTION_STATUS)
    )

    assert_equal "update", result[:response_action]
    assert_equal "modal", result[:view]["type"]
  end

  test "replaces home modal with incident creation modal for new action" do
    Slack::Modals::IncidentCreation.expects(:build).returns({ "type" => "modal", "title" => { "type" => "plain_text", "text" => "New Incident" } })

    result = Interactions::HomeContinueHandler.execute(
      build_interaction(selected: Identifiers::HOME_ACTION_NEW)
    )

    assert_equal "update", result[:response_action]
    assert_equal "modal", result[:view]["type"]
  end

  test "postmortem action surfaces the denial message when entitlement is blocked" do
    message = deny_entitlements!("Your trial has ended — upgrade to keep using AI.")
    closed = Incident.create!(
      workspace: @workspace,
      declared_by: workspace_memberships(:alice_workspace_one),
      incident_status: incident_statuses(:resolved_ws1),
      incident_severity: incident_severities(:critical_ws1),
      name: "Closed, no postmortem",
      is_private: false,
      channel_id: "C_HOME_CLOSED",
      source: Incident::SOURCE_SLACK,
      resolved_at: 1.hour.ago
    )

    result = Interactions::HomeContinueHandler.execute(
      build_interaction(selected: Identifiers::HOME_ACTION_POSTMORTEM, channel_id: closed.channel_id)
    )

    assert_equal "errors", result[:response_action]
    assert_equal message, result[:errors]["action_select_block"]
  end

  private

  def build_interaction(selected:, channel_id: @incident.channel_id)
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_SUBMISSION,
      team_id: @workspace.platform_id,
      user_id: "U12345678",
      callback_id: Identifiers::INCIDENT_HOME_MODAL,
      private_metadata: { channel_id: channel_id }.to_json,
      values: {
        "action_select_block" => {
          Identifiers::HOME_ACTION_SELECT => {
            "selected_option" => { "value" => selected }
          }
        }
      }
    )
  end
end
