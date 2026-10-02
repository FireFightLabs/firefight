require "test_helper"

class CodeAgentControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @session, @token = CodeAgentSession.open!(workspace: @workspace, choice: FirefightAi::ModelChoice.new(model: "claude-sonnet-4-5", provider: "anthropic"),
                                              repository: "acme/api")
  end

  test "a call with the session's token reaches the model, streams back, and is counted against the budget" do
    FirefightAi::ModelProxy.any_instance.expects(:forward).with { |path:, body:, model:, headers:| path == "messages" && body == "{\"x\":1}" && model == "claude-sonnet-4-5" && headers["anthropic-version"] == "2023-06-01" }
                           .multiple_yields([ :start, 200, "text/event-stream" ], [ :chunk, "data: {}\n\n" ])
    FirefightAi::ModelProxy.any_instance.stubs(:usage).returns(FirefightAi::ModelProxy::Usage.new(input: 1000, output: 100, cache_read: 0, cache_write: 0))
    FirefightAi::ModelProxy.any_instance.stubs(:status).returns(200)
    FirefightAi.stubs(:cost_micros).returns(1_500)
    FirefightAi.configuration.stubs(:provider_settings).returns(anthropic_api_key: "sk-firefight")

    post "/code_agent/anthropic/messages", params: "{\"x\":1}", headers: { "x-api-key" => @token, "anthropic-version" => "2023-06-01", "CONTENT_TYPE" => "application/json" }

    assert_response :success
    assert_equal "data: {}\n\n", response.body
    assert_equal 1_500, @session.reload.spent_micros
    inference = Inference.find_by!(inferable: @session)
    assert_equal [ CodeAgentSession::FEATURE, 1000, 100, 1_500 ], [ inference.feature, inference.input_tokens, inference.output_tokens, inference.cost_micros ]
  end

  test "no token, an ended session or a spent budget never reaches the model" do
    FirefightAi::ModelProxy.any_instance.expects(:forward).never

    post "/code_agent/anthropic/messages", params: "{}", headers: { "x-api-key" => "wrong" }
    assert_response :unauthorized

    @session.update_columns(spent_micros: @session.budget_micros)
    post "/code_agent/anthropic/messages", params: "{}", headers: { "Authorization" => "Bearer #{@token}" }
    assert_response :forbidden
    assert_equal CodeAgentSession::OVER_BUDGET, response.parsed_body.dig("error", "message")

    @session.close!
    post "/code_agent/anthropic/messages", params: "{}", headers: { "x-api-key" => @token }
    assert_response :unauthorized
  end
end
