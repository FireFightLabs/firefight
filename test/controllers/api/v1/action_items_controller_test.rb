require "test_helper"

class Api::V1::ActionItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @other = workspace_memberships(:bob_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @key = api_keys(:full_access_key)

    stub_post_message
    stub_update_message
  end

  test "lists the incident's open work with who holds each piece" do
    get api_v1_incident_action_items_url(@incident), headers: api_headers, as: :json

    assert_response :success
    listed = json_response["action_items"].index_by { |item| item["id"] }
    open_item = incident_actions(:inc1_action_open)
    assert_equal open_item.description, listed[open_item.id]["description"]
    assert_equal @other.actor_display_name, listed[open_item.id].dig("assignee", "name")
  end

  test "an action on an incident that is over is refused, and a follow-up is not" do
    over = incidents(:resolved_minor_ws1)

    post api_v1_incident_action_items_url(over),
         params: { description: "Too late", kind: IncidentAction::ACTION_TYPE_ACTION },
         headers: api_headers, as: :json

    assert_response :unprocessable_entity
    assert_equal "incident_not_active", json_response.dig("error", "type")
    assert_match(/Add a follow-up instead/, json_response.dig("error", "message"))

    post api_v1_incident_action_items_url(over),
         params: { description: "Add an alert for this", kind: IncidentAction::ACTION_TYPE_FOLLOWUP },
         headers: api_headers, as: :json

    assert_response :created
  end

  test "creating an item records the key as having raised it" do
    post api_v1_incident_action_items_url(@incident),
         params: { description: "Drain replica 2", kind: IncidentAction::ACTION_TYPE_ACTION },
         headers: api_headers, as: :json

    assert_response :created
    action = @incident.incident_actions.find_by!(description: "Drain replica 2")
    assert_equal @key, action.created_by
    assert_equal IncidentAction::STATUS_OPEN, action.status
  end

  test "creating an item assigned to somebody starts it in progress" do
    post api_v1_incident_action_items_url(@incident),
         params: { description: "Page the DBA", assignee_id: @other.user.email },
         headers: api_headers, as: :json

    assert_response :created
    action = @incident.incident_actions.find_by!(description: "Page the DBA")
    assert_equal @other, action.assignee
    assert_equal IncidentAction::STATUS_IN_PROGRESS, action.status
  end

  # Omitting the assignee means I am taking this, the button a person presses rather than a separate endpoint.
  test "an assignee of nobody means the key takes the item itself" do
    action = incident_actions(:inc1_followup)

    patch api_v1_incident_action_item_url(@incident, action),
          params: { assignee_id: nil }, headers: api_headers, as: :json

    assert_response :success
    assert_equal @key, action.reload.assignee
    assert @incident.incident_events.exists?(event_type: IncidentEvent::ACTION_PICKED_UP)
  end

  test "naming somebody else hands the item over and announces it" do
    action = incident_actions(:inc1_action_in_progress)

    patch api_v1_incident_action_item_url(@incident, action),
          params: { assignee_id: @other.user.email }, headers: api_headers, as: :json

    assert_response :success
    assert_equal @other, action.reload.assignee
    assert @incident.incident_events.exists?(event_type: IncidentEvent::ACTION_REASSIGNED)
  end

  test "setting the status to done finishes the item" do
    action = incident_actions(:inc1_action_open)

    patch api_v1_incident_action_item_url(@incident, action),
          params: { status: IncidentAction::STATUS_DONE }, headers: api_headers, as: :json

    assert_response :success
    assert action.reload.done?
    event = @incident.incident_events.find_by!(event_type: IncidentEvent::ACTION_COMPLETED)
    assert_equal @key, event.actor
  end

  test "a person this workspace has never heard of is refused" do
    post api_v1_incident_action_items_url(@incident),
         params: { description: "Nope", assignee_id: "nobody@example.com" },
         headers: api_headers, as: :json

    assert_response :not_found
  end

  test "a read-only key cannot raise an item" do
    post api_v1_incident_action_items_url(@incident),
         params: { description: "Should never exist" },
         headers: api_headers(token: "ff_test_read_only_token_12345678"), as: :json

    assert_response :forbidden
    assert_nil @incident.incident_actions.find_by(description: "Should never exist")
  end

  test "another workspace's incident is not reachable" do
    get api_v1_incident_action_items_url(incidents(:active_p0_ws2)), headers: api_headers, as: :json

    assert_response :not_found
  end

  test "a description renames the item, and status open reopens a done one and lets go of one in progress" do
    action = incident_actions(:inc1_action_in_progress)

    patch api_v1_incident_action_item_url(@incident, action), params: { description: "Restart every worker" }, headers: api_headers, as: :json
    assert_response :success
    assert_equal "Restart every worker", action.reload.description

    patch api_v1_incident_action_item_url(@incident, action), params: { status: IncidentAction::STATUS_OPEN }, headers: api_headers, as: :json
    assert_equal [ IncidentAction::STATUS_OPEN, nil ], [ action.reload.status, action.assignee ]
    assert @incident.incident_events.exists?(event_type: IncidentEvent::ACTION_UNASSIGNED)

    action.update!(status: IncidentAction::STATUS_DONE)
    patch api_v1_incident_action_item_url(@incident, action), params: { status: IncidentAction::STATUS_OPEN }, headers: api_headers, as: :json
    assert_equal IncidentAction::STATUS_OPEN, action.reload.status
    assert @incident.incident_events.exists?(event_type: IncidentEvent::ACTION_REOPENED)

    patch api_v1_incident_action_item_url(@incident, action), params: { description: "" }, headers: api_headers, as: :json
    assert_response :unprocessable_entity
  end

  test "a title past 3,000 characters is refused with how long it is" do
    action = incident_actions(:inc1_action_in_progress)
    title = action.description

    patch api_v1_incident_action_item_url(@incident, action), params: { description: "a" * 3_001 }, headers: api_headers, as: :json

    assert_response :unprocessable_entity
    assert_includes response.body, "Please shorten it to 3,000 characters or fewer (it's 3,001 now)."
    assert_equal title, action.reload.description
  end

  test "a refused status leaves the rename in the same request unwritten" do
    action = incident_actions(:inc1_action_in_progress)
    action.update!(status: IncidentAction::STATUS_DONE)
    title = action.description

    patch api_v1_incident_action_item_url(@incident, action),
          params: { description: "Restart every worker", status: IncidentAction::STATUS_DONE }, headers: api_headers, as: :json

    assert_response :unprocessable_entity
    assert_equal title, action.reload.description
    assert_not @incident.incident_events.exists?(event_type: IncidentEvent::ACTION_RENAMED)
  end
end
