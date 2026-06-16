require "test_helper"

class IncidentActionsControllerTest < ActionDispatch::IntegrationTest
  fixtures :workspaces, :users, :workspace_memberships,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @user = users(:alice)
    @member = workspace_memberships(:alice_workspace_one)
    @assignee = workspace_memberships(:bob_workspace_one)
    sign_in(@user, @workspace)

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

  test "create posts the action and redirects to the incident" do
    stub_post_message

    assert_difference -> { @incident.incident_actions.count }, 1 do
      post incident_actions_path(incident_id: @incident.id), params: {
        action_type: IncidentAction::ACTION_TYPE_ACTION,
        description: "Restart the service",
        assignee_id: @assignee.platform_user_id
      }
    end

    action = @incident.incident_actions.find_by!(description: "Restart the service")
    assert_equal @member, action.created_by
    assert_equal @assignee, action.assignee
    assert_equal IncidentAction::ACTION_TYPE_ACTION, action.action_type
    assert_redirected_to incident_path(@incident)
  end

  test "create leaves the action unassigned when assignee_id is blank" do
    stub_post_message

    post incident_actions_path(incident_id: @incident.id), params: {
      action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: "Check the logs",
      assignee_id: ""
    }

    action = @incident.incident_actions.find_by!(description: "Check the logs")
    assert_nil action.assignee
    assert_redirected_to incident_path(@incident)
  end

  test "create swallows AdapterError from the Slack post and still redirects" do
    Slack::WorkspaceAdapter.any_instance
      .stubs(:post_action_message)
      .raises(AdapterError::NotFound.new("channel gone"))

    assert_difference -> { @incident.incident_actions.count }, 1 do
      post incident_actions_path(incident_id: @incident.id), params: {
        action_type: IncidentAction::ACTION_TYPE_ACTION,
        description: "Page the on-call"
      }
    end

    action = @incident.incident_actions.find_by!(description: "Page the on-call")
    assert_nil action.message_ts
    assert_redirected_to incident_path(@incident)
  end

  private

  def sign_in(user, workspace)
    ApplicationController.any_instance.stubs(:current_user).returns(user)
    ApplicationController.any_instance.stubs(:current_workspace).returns(workspace)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
  end
end
