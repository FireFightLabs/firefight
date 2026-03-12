require "test_helper"

class Interactions::HomeContinueHandlerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "replaces home modal with incident action modal" do
    adapter = mock("workspace_adapter")
    WorkspaceAdapter.expects(:for).with(@workspace).returns(adapter)
    adapter.expects(:build_incident_update_view).returns({ "type" => "modal", "title" => { "type" => "plain_text", "text" => "Update Incident" } })

    result = Interactions::HomeContinueHandler.execute(
      build_interaction(selected: Identifiers::HOME_ACTION_STATUS)
    )

    assert_equal "update", result[:response_action]
    assert_equal "modal", result[:view]["type"]
  end

  test "replaces home modal with incident creation modal for new action" do
    adapter = mock("workspace_adapter")
    WorkspaceAdapter.expects(:for).with(@workspace).returns(adapter)
    adapter.expects(:build_incident_creation_view).returns({ "type" => "modal", "title" => { "type" => "plain_text", "text" => "New Incident" } })

    result = Interactions::HomeContinueHandler.execute(
      build_interaction(selected: Identifiers::HOME_ACTION_NEW)
    )

    assert_equal "update", result[:response_action]
    assert_equal "modal", result[:view]["type"]
  end

  private

  def build_interaction(selected:)
    Interaction.new(
      platform: Platforms::SLACK,
      type: Interaction::VIEW_SUBMISSION,
      team_id: @workspace.platform_id,
      user_id: "U12345678",
      callback_id: Identifiers::INCIDENT_HOME_MODAL,
      private_metadata: { channel_id: @incident.channel_id }.to_json,
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
