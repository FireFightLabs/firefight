require "test_helper"

class IncidentActionsControllerTest < ActionDispatch::IntegrationTest
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

  test "create provisions the assignee when they don't have a workspace membership yet" do
    stub_post_message
    stub_get_user_info

    assert_difference -> { @workspace.workspace_memberships.count }, 1 do
      post incident_actions_path(incident_id: @incident.id), params: {
        action_type: IncidentAction::ACTION_TYPE_ACTION,
        description: "Assign to new employee",
        assignee_id: "U_NEW_USER"
      }
    end

    action = @incident.incident_actions.find_by!(description: "Assign to new employee")
    assert_equal "U_NEW_USER", action.assignee.platform_user_id
    assert_redirected_to incident_path(@incident)
  end

  test "create assigns from a membership id, which is how the picker offers an existing member" do
    stub_post_message
    WorkspaceMemberProvisioner.expects(:find_or_provision!).never

    post incident_actions_path(incident_id: @incident.id), params: {
      action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: "Roll back the deploy",
      assignee_id: @assignee.id
    }

    action = @incident.incident_actions.find_by!(description: "Roll back the deploy")
    assert_equal @assignee, action.assignee
    assert_redirected_to incident_path(@incident)
  end

  test "create alerts and skips the action when the assignee profile can't be loaded" do
    Slack::WorkspaceAdapter.any_instance
      .stubs(:get_user_info)
      .raises(AdapterError.new("users.info failed"))

    assert_no_difference [ -> { @incident.incident_actions.count }, -> { @workspace.workspace_memberships.count } ] do
      post incident_actions_path(incident_id: @incident.id), params: {
        action_type: IncidentAction::ACTION_TYPE_ACTION,
        description: "Assign to new employee",
        assignee_id: "U_NEW_USER"
      }
    end

    assert_redirected_to incident_path(@incident)
    assert_equal IncidentActionsController::ASSIGNEE_UNAVAILABLE, flash[:alert]
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

  # Working an item from the page

  test "picking up an unassigned item takes it and starts it" do
    action = open_action

    patch pick_up_incident_action_path(@incident, action)

    assert_redirected_to incident_path(@incident)
    assert_equal @member, action.reload.assignee
    assert_equal IncidentAction::STATUS_IN_PROGRESS, action.status
    assert @incident.incident_events.exists?(event_type: IncidentEvent::ACTION_PICKED_UP)
  end

  test "handing an item to someone else is a reassignment, not a pick up" do
    action = open_action
    other = workspace_memberships(:bob_workspace_one)

    patch assign_incident_action_path(@incident, action), params: { member_id: other.id }

    assert_equal other, action.reload.assignee
    assert @incident.incident_events.exists?(event_type: IncidentEvent::ACTION_REASSIGNED)
  end

  test "completing an item records it done" do
    action = open_action

    patch complete_incident_action_path(@incident, action)

    assert action.reload.done?
    assert @incident.incident_events.exists?(event_type: IncidentEvent::ACTION_COMPLETED)
  end

  test "an item that is already done is left alone" do
    action = open_action
    IncidentActionService.new(@workspace).complete_action(action: action, completed_by: @member)

    assert_no_difference -> { @incident.incident_events.where(event_type: IncidentEvent::ACTION_COMPLETED).count } do
      patch complete_incident_action_path(@incident, action)
    end
  end

  test "picking up an item someone already holds does nothing" do
    action = open_action
    other = workspace_memberships(:bob_workspace_one)
    IncidentActionService.new(@workspace).pick_up_action(action: action, picked_up_by: other)

    patch pick_up_incident_action_path(@incident, action)

    assert_equal other, action.reload.assignee
  end

  test "another workspace's item is not reachable" do
    action = open_action

    patch complete_incident_action_path(incidents(:active_p0_ws2), action)

    assert_response :not_found
  end

  # An agent has no user behind it, so the page has to render an item a
  # machine holds without trying to load one.
  test "the incident page renders an item held by an agent" do
    agent = @workspace.agents.create!(name: "Support agent", slug: "support_agent")
    action = open_action
    IncidentActionService.new(@workspace).assign_action(
      action: action, assignee: agent, assigned_by: @member
    )

    # The actions prop is deferred, so it only renders when asked for.
    get incident_path(@incident), headers: {
      "X-Inertia" => "true",
      "X-Inertia-Version" => InertiaRails.configuration.version.to_s,
      "X-Inertia-Partial-Component" => "incidents/index",
      "X-Inertia-Partial-Data" => "actions"
    }

    assert_response :success
    assignee = JSON.parse(response.body).dig("props", "actions", 0, "assignee")
    assert_equal agent.name, assignee["name"]
    assert_equal Ability::Principal::KIND_AGENT, assignee["kind"]
  end

  private

  def open_action
    stub_post_message
    stub_update_message
    stub_get_permalink
    IncidentActionService.new(@workspace).create_action(
      incident: @incident,
      created_by: @member,
      action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: "Drain replica 2"
    )
  end
end
