require "test_helper"

class Api::V1::InteractionsControllerTest < ActionDispatch::IntegrationTest
  fixtures :workspaces, :users

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @user = users(:alice)
  end

  test "should accept valid view_submission interaction" do
    payload = {
    type: "view_submission",
    team: { id: @workspace.platform_id, domain: "test-workspace" },
    user: { id: "U12345678", username: "alice", name: "Alice Smith" },
    view: {
      callback_id: Identifiers::INCIDENT_CREATION_MODAL,
      type: "modal",
      private_metadata: "",
      state: {
        values: {
          name_block: {
            name_input: { type: "plain_text_input", value: "Test Incident" }
          },
          severity_block: {
            severity_select: { type: "static_select", selected_option: { value: "critical" } }
          },
          summary_block: {
            summary_input: { type: "plain_text_input", value: "Test summary" }
          }
        }
      }
    }
    }

    request_data = slack_interaction_request(payload)

    post api_v1_interactions_url,
       params: request_data[:body],
       headers: request_data[:headers]

    assert_response :success
  end

  test "should reject interaction without signature" do
    payload = {
    type: "view_submission",
    team: { id: @workspace.platform_id },
    user: { id: "U12345678" }
    }

    InteractionDispatcher.expects(:dispatch).never

    post api_v1_interactions_url,
       params: { payload: payload.to_json }

    assert_response :unauthorized
  end

  test "should reject interaction with invalid signature" do
    request_data = slack_interaction_request(
    team: { id: @workspace.platform_id }
    )

    # Tamper with signature
    request_data[:headers]["X-Slack-Signature"] = "v0=invalid_signature"

    InteractionDispatcher.expects(:dispatch).never

    post api_v1_interactions_url,
       params: request_data[:body],
       headers: request_data[:headers]

    assert_response :unauthorized
  end

  test "should handle block_actions interaction" do
    payload = {
    type: "block_actions",
    team: { id: @workspace.platform_id },
    user: { id: "U12345678" },
    actions: [
      { type: "button", action_id: "test_button", value: "test_value" }
    ]
    }

    request_data = slack_interaction_request(payload)

    post api_v1_interactions_url,
       params: request_data[:body],
       headers: request_data[:headers]

    assert_response :success
  end

  test "a click from a workspace Firefight does not know is dropped with 200 and never dispatched" do
    InteractionDispatcher.expects(:dispatch).never
    payload = {
      type: "block_actions",
      team: { id: "T_NOBODY" },
      user: { id: "U12345678" },
      actions: [ { type: "button", action_id: Identifiers::ACCEPT_INCIDENT, value: "x" } ]
    }

    request_data = slack_interaction_request(payload)
    post api_v1_interactions_url, params: request_data[:body], headers: request_data[:headers]

    assert_response :success
  end

  test "should handle view_closed interaction" do
    payload = {
    type: "view_closed",
    team: { id: @workspace.platform_id },
    user: { id: "U12345678" },
    view: {
      callback_id: Identifiers::INCIDENT_CREATION_MODAL,
      type: "modal"
    }
    }

    request_data = slack_interaction_request(payload)

    post api_v1_interactions_url,
       params: request_data[:body],
       headers: request_data[:headers]

    assert_response :success
  end

  test "should handle unknown interaction type" do
    payload = {
    type: "unknown_type",
    team: { id: @workspace.platform_id },
    user: { id: "U12345678" }
    }

    request_data = slack_interaction_request(payload)

    post api_v1_interactions_url,
       params: request_data[:body],
       headers: request_data[:headers]

    assert_response :success
  end

  test "should return bad request for missing payload" do
    body = ""
    headers = generate_slack_signature(body: body)

    InteractionDispatcher.expects(:dispatch).never

    post api_v1_interactions_url,
         params: body,
         headers: headers

    assert_response :bad_request
    assert_equal "Invalid payload", JSON.parse(response.body)["error"]
  end

  test "should return bad request for invalid JSON payload" do
    body = "payload=not_valid_json"
    headers = generate_slack_signature(body: body)

    InteractionDispatcher.expects(:dispatch).never

    post api_v1_interactions_url,
       params: body,
       headers: headers

    assert_response :bad_request
    assert_equal "Invalid payload", JSON.parse(response.body)["error"]
  end

  test "should extract form values from view_submission" do
    payload = {
    type: "view_submission",
    team: { id: @workspace.platform_id },
    user: { id: "U12345678" },
    view: {
      callback_id: Identifiers::INCIDENT_CREATION_MODAL,
      state: {
        values: {
          name_block: {
            name_input: { value: "Production Database Down" }
          },
          severity_block: {
            severity_select: { selected_option: { value: "critical" } }
          },
          summary_block: {
            summary_input: { value: "Database is not responding to queries" }
          }
        }
      }
    }
    }

    request_data = slack_interaction_request(payload)

    post api_v1_interactions_url,
       params: request_data[:body],
       headers: request_data[:headers]

    assert_response :success

    # Verify the payload was parsed correctly (check logs in actual implementation)
    # When incident creation is implemented, this will create the incident
  end

  test "should handle private_metadata in view_submission" do
    metadata = {
    workspace_id: @workspace.id,
    user_id: "U12345678",
    channel_id: "C12345678"
    }

    payload = {
    type: "view_submission",
    team: { id: @workspace.platform_id },
    user: { id: "U12345678" },
    view: {
      callback_id: Identifiers::INCIDENT_CREATION_MODAL,
      private_metadata: metadata.to_json,
      state: { values: {} }
    }
    }

    request_data = slack_interaction_request(payload)

    post api_v1_interactions_url,
       params: request_data[:body],
       headers: request_data[:headers]

    assert_response :success
  end

  # Phase 7 Interactive Component Tests

  test "should handle preview_announcement button click" do
    # Set up workspace with incidents channel
    @workspace.update!(incidents_channel_id: "C12345678")

    payload = {
    type: "block_actions",
    team: { id: @workspace.platform_id },
    user: { id: "U12345678" },
    channel: { id: "C12345678" },
    trigger_id: "12345.67890.trigger",
    actions: [
      { action_id: Identifiers::PREVIEW_ANNOUNCEMENT, type: "button" }
    ]
    }

    request_data = slack_interaction_request(payload)

    # Stub the Slack API call
    stub_post_ephemeral
    post api_v1_interactions_url,
         params: request_data[:body],
         headers: request_data[:headers]

    assert_response :success
    response_json = JSON.parse(response.body)
    assert_equal "clear", response_json["response_action"]
  end

  test "should handle share_incidents_channel button click" do
    @workspace.update!(incidents_channel_id: "C12345678")

    payload = {
    type: "block_actions",
    team: { id: @workspace.platform_id },
    user: { id: "U12345678" },
    channel: { id: "C12345678" },
    trigger_id: "12345.67890.trigger",
    actions: [
      { action_id: Identifiers::SHARE_INCIDENTS_CHANNEL, type: "button" }
    ]
    }

    request_data = slack_interaction_request(payload)

    stub_open_modal
    post api_v1_interactions_url,
         params: request_data[:body],
         headers: request_data[:headers]

    assert_response :success
    response_json = JSON.parse(response.body)
    assert_equal "clear", response_json["response_action"]
  end

  test "should handle share_incidents_channel with expired trigger" do
    @workspace.update!(incidents_channel_id: "C12345678")

    payload = {
    type: "block_actions",
    team: { id: @workspace.platform_id },
    user: { id: "U12345678" },
    channel: { id: "C12345678" },
    trigger_id: "expired.trigger",
    actions: [
      { action_id: Identifiers::SHARE_INCIDENTS_CHANNEL, type: "button" }
    ]
    }

    request_data = slack_interaction_request(payload)

    stub_open_modal(raises: AdapterError::TriggerExpired.new("expired"))
    post api_v1_interactions_url,
         params: request_data[:body],
         headers: request_data[:headers]

    assert_response :success
    response_json = JSON.parse(response.body)
    assert_equal "errors", response_json["response_action"]
    assert response_json["errors"]["base"].present?
  end

  test "should handle share modal submission with targets" do
    @workspace.update!(incidents_channel_id: "C12345678")

    payload = {
    type: "view_submission",
    team: { id: @workspace.platform_id },
    user: { id: "U12345678" },
    view: {
      callback_id: Identifiers::SHARE_INCIDENTS_CHANNEL_MODAL,
      state: {
        values: {
          share_target_block: {
            share_target_select: {
              type: "multi_conversations_select",
              selected_conversations: [ "C11111111", "C22222222" ]
            }
          }
        }
      }
    }
    }

    request_data = slack_interaction_request(payload)

    stub_post_message
    post api_v1_interactions_url,
         params: request_data[:body],
         headers: request_data[:headers]

    assert_response :success
    response_json = JSON.parse(response.body)
    assert_equal "clear", response_json["response_action"]
  end

  test "should handle share modal submission with no targets" do
    @workspace.update!(incidents_channel_id: "C12345678")

    payload = {
    type: "view_submission",
    team: { id: @workspace.platform_id },
    user: { id: "U12345678" },
    view: {
      callback_id: Identifiers::SHARE_INCIDENTS_CHANNEL_MODAL,
      state: {
        values: {
          share_target_block: {
            share_target_select: {
              type: "multi_conversations_select",
              selected_conversations: []
            }
          }
        }
      }
    }
    }

    request_data = slack_interaction_request(payload)

    post api_v1_interactions_url,
       params: request_data[:body],
       headers: request_data[:headers]

    assert_response :success
    response_json = JSON.parse(response.body)
    assert_equal "errors", response_json["response_action"]
    assert response_json["errors"]["share_target_block"].present?
  end

  test "should handle disabled preview buttons" do
    @workspace.update!(incidents_channel_id: "C12345678")

    [ Identifiers::PREVIEW_HOMEPAGE_DISABLED, Identifiers::PREVIEW_SUBSCRIBE_DISABLED ].each do |action_id|
    payload = {
      type: "block_actions",
      team: { id: @workspace.platform_id },
      user: { id: "U12345678" },
      channel: { id: "C12345678" },
      actions: [
        { action_id: action_id, type: "button" }
      ]
    }

    request_data = slack_interaction_request(payload)

    post api_v1_interactions_url,
         params: request_data[:body],
         headers: request_data[:headers]

    assert_response :success
    response_json = JSON.parse(response.body)
    assert_equal "clear", response_json["response_action"]
    end
  end

  test "should handle unhandled modal callback_id gracefully" do
    payload = {
    type: "view_submission",
    team: { id: @workspace.platform_id },
    user: { id: "U12345678" },
    view: {
      callback_id: "unknown_modal",
      state: { values: {} }
    }
    }

    request_data = slack_interaction_request(payload)

    post api_v1_interactions_url,
       params: request_data[:body],
       headers: request_data[:headers]

    # Should log but not crash
    assert_response :success
  end
end
