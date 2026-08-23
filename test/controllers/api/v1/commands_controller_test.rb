require "test_helper"

class Api::V1::CommandsControllerTest < ActionDispatch::IntegrationTest
  fixtures :workspaces, :users, :workspace_memberships

  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "should dispatch valid slack command and return 200" do
    CommandDispatcher.expects(:dispatch).once.returns(nil)

    request_data = slack_command_request(
      team_id: @workspace.platform_id,
      user_id: "U12345678",
      text: "help"
    )

    post api_v1_commands_url,
         params: request_data[:body],
         headers: request_data[:headers]

    assert_response :success
  end

  test "should pass parsed command to dispatcher" do
    dispatched_command = nil
    CommandDispatcher.stubs(:dispatch).with { |cmd| dispatched_command = cmd; true }.returns(nil)

    request_data = slack_command_request(
      team_id: @workspace.platform_id,
      user_id: "U12345678",
      text: "help me",
      channel_id: "C12345678"
    )

    post api_v1_commands_url,
         params: request_data[:body],
         headers: request_data[:headers]

    assert_equal Platforms::SLACK, dispatched_command.platform
    assert_equal @workspace.id, dispatched_command.workspace_id
    assert_equal "U12345678", dispatched_command.user_id
    assert_equal "help me", dispatched_command.text
    assert_equal "C12345678", dispatched_command.channel_id
  end

  test "should render ephemeral response in body when handler returns one" do
    CommandDispatcher.stubs(:dispatch).returns(
      { response_type: Command::EPHEMERAL, text: "Not in incident channel" }
    )

    request_data = slack_command_request(team_id: @workspace.platform_id, text: "summary")
    post api_v1_commands_url, params: request_data[:body], headers: request_data[:headers]

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "ephemeral", body["response_type"]
    assert_equal "Not in incident channel", body["text"]
  end

  test "should include blocks in ephemeral response when provided" do
    blocks = [ { type: "section", text: { type: "mrkdwn", text: "*Timeline*" } } ]
    CommandDispatcher.stubs(:dispatch).returns(
      { response_type: Command::EPHEMERAL, text: "Timeline", blocks: blocks }
    )

    request_data = slack_command_request(team_id: @workspace.platform_id, text: "timeline")
    post api_v1_commands_url, params: request_data[:body], headers: request_data[:headers]

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "section", body["blocks"].first["type"]
  end

  test "should return empty 200 when handler returns nil" do
    CommandDispatcher.stubs(:dispatch).returns(nil)

    request_data = slack_command_request(team_id: @workspace.platform_id, text: "")
    post api_v1_commands_url, params: request_data[:body], headers: request_data[:headers]

    assert_response :success
    assert_empty response.body
  end

  test "should render ephemeral error when dispatch raises" do
    CommandDispatcher.stubs(:dispatch).raises(StandardError.new("boom"))

    request_data = slack_command_request(team_id: @workspace.platform_id, text: "help")
    post api_v1_commands_url, params: request_data[:body], headers: request_data[:headers]

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "ephemeral", body["response_type"]
    assert_includes body["text"], "something went wrong"
  end

  test "should return 200 without dispatching when workspace is unknown" do
    CommandDispatcher.expects(:dispatch).never

    request_data = slack_command_request(team_id: "TNONEXIST")
    post api_v1_commands_url, params: request_data[:body], headers: request_data[:headers]

    assert_response :success
  end

  test "a first-time user is provisioned exactly once, on the way through the dispatcher" do
    stub_get_user_info
    stub_open_modal
    WorkspaceMemberProvisioner.expects(:find_or_provision!).once.returns(nil)

    request_data = slack_command_request(
      team_id: @workspace.platform_id,
      user_id: "U_NEW_USER",
      text: Identifiers::SUBCOMMAND_NEW
    )
    post api_v1_commands_url, params: request_data[:body], headers: request_data[:headers]

    assert_response :success
  end

  test "a user whose profile cannot be read is refused with a message rather than dropped" do
    WorkspaceMemberProvisioner.stubs(:find_or_provision!).raises(StandardError.new("API down"))

    request_data = slack_command_request(team_id: @workspace.platform_id, text: Identifiers::SUBCOMMAND_NEW)
    post api_v1_commands_url, params: request_data[:body], headers: request_data[:headers]

    assert_response :success
    assert_equal AuthorizedDispatch::UNRESOLVED_MESSAGE, JSON.parse(response.body)["text"]
  end

  test "should reject request without signature" do
    CommandDispatcher.expects(:dispatch).never

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
    CommandDispatcher.expects(:dispatch).never

    request_data = slack_command_request(team_id: @workspace.platform_id)
    request_data[:headers]["X-Slack-Signature"] = "v0=invalid_signature"

    post api_v1_commands_url,
         params: request_data[:body],
         headers: request_data[:headers]

    assert_response :unauthorized
  end

  test "should reject request with old timestamp (replay attack)" do
    CommandDispatcher.expects(:dispatch).never

    old_timestamp = (Time.now - SlackConstants::REPLAY_ATTACK_WINDOW - 1.minute).to_i
    request_data = slack_command_request(team_id: @workspace.platform_id)

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
end
