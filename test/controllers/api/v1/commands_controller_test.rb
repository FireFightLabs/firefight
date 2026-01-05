require "test_helper"

class Api::V1::CommandsControllerTest < ActionDispatch::IntegrationTest
  fixtures :workspaces

  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "should enqueue job for valid slack command" do
    request_data = slack_command_request(
      team_id: @workspace.platform_id,
      user_id: "U12345678",
      text: "help"
    )

    assert_enqueued_with(job: ProcessCommandJob) do
      post api_v1_commands_url,
           params: request_data[:body],
           headers: request_data[:headers]
    end

    assert_response :success
  end

  test "should reject request without signature" do
    params = {
      team_id: @workspace.platform_id,
      user_id: "U12345678",
      text: "help"
    }

    post api_v1_commands_url, params: params

    assert_response :unauthorized
    assert_equal "Unauthorized", JSON.parse(response.body)["error"]
  end

  test "should reject request with invalid signature" do
    request_data = slack_command_request(team_id: @workspace.platform_id)

    # Tamper with signature
    request_data[:headers]["X-Slack-Signature"] = "v0=invalid_signature"

    post api_v1_commands_url,
         params: request_data[:body],
         headers: request_data[:headers]

    assert_response :unauthorized
  end

  test "should reject request with old timestamp (replay attack)" do
    old_timestamp = (Time.now - SlackConstants::REPLAY_ATTACK_WINDOW - 1.minute).to_i

    request_data = slack_command_request(
      team_id: @workspace.platform_id,
      timestamp: old_timestamp
    )

    # Generate valid signature for old timestamp
    sig_basestring = "#{SlackConstants::SIGNATURE_VERSION}:#{old_timestamp}:#{request_data[:body]}"
    signature = "#{SlackConstants::SIGNATURE_VERSION}=" +
                OpenSSL::HMAC.hexdigest("SHA256", SlackConstants::SIGNING_SECRET, sig_basestring)

    request_data[:headers]["X-Slack-Signature"] = signature
    request_data[:headers]["X-Slack-Request-Timestamp"] = old_timestamp.to_s

    post api_v1_commands_url,
         params: request_data[:body],
         headers: request_data[:headers]

    assert_response :unauthorized
  end

  test "should return 404 when workspace not found" do
    request_data = slack_command_request(
      team_id: "TNONEXIST" # Non-existent workspace
    )

    post api_v1_commands_url,
         params: request_data[:body],
         headers: request_data[:headers]

    assert_response :not_found
    assert_equal "Not found", JSON.parse(response.body)["error"]
  end

  test "should handle empty command text" do
    request_data = slack_command_request(
      team_id: @workspace.platform_id,
      text: ""
    )

    assert_enqueued_with(job: ProcessCommandJob) do
      post api_v1_commands_url,
           params: request_data[:body],
           headers: request_data[:headers]
    end

    assert_response :success
  end

  test "should handle command with text" do
    request_data = slack_command_request(
      team_id: @workspace.platform_id,
      text: "status"
    )

    assert_enqueued_with(job: ProcessCommandJob) do
      post api_v1_commands_url,
           params: request_data[:body],
           headers: request_data[:headers]
    end

    assert_response :success
  end

  test "should pass all command parameters to job" do
    expected_params = {
      token: "test-token",
      team_id: @workspace.platform_id,
      team_domain: "test-workspace",
      channel_id: "C12345678",
      channel_name: "general",
      user_id: "U12345678",
      user_name: "alice",
      command: "/firefight",
      text: "help me",
      response_url: "https://hooks.slack.com/commands/T12345678/12345/abc123",
      trigger_id: "123456.789.abc123",
      api_app_id: "A12345678"
    }

    request_data = slack_command_request(expected_params)

    assert_enqueued_with(
      job: ProcessCommandJob,
      args: ->(args) { args[0] == Platforms::SLACK && args[1]["text"] == "help me" }
    ) do
      post api_v1_commands_url,
           params: request_data[:body],
           headers: request_data[:headers]
    end

    assert_response :success
  end
end
