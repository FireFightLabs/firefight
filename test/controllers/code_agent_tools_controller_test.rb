require "test_helper"

class CodeAgentToolsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @session, @token = CodeAgentSession.open!(workspace: @workspace, choice: FirefightAi::ModelChoice.new(model: "gpt-4o", provider: "openai"),
                                              repository: "acme/api")
  end

  test "the coding agent searches the web on its session's token, and the ledger holds it under the workspace" do
    WebLookup.expects(:search).with("pg pool timeout", domains: []).returns("[1] Pool\nhttps://node-postgres.com/apis/pool\nidleTimeoutMillis")

    post "/code_agent/tools", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "search_web", arguments: { query: "pg pool timeout" } } }.to_json,
                              headers: { "Authorization" => "Bearer #{@token}", "CONTENT_TYPE" => "application/json" }

    assert_response :success
    assert_includes response.parsed_body.dig("result", "content", 0, "text").to_s, "https://node-postgres.com/apis/pool", response.body
    call = Ability::Invocation.find_by!(workspace: @workspace, action_key: Ability::Action::WEB_READ)
    assert_equal [ AbilityGateway::SOURCE_CODE_AGENT, Ability::Invocation::DECISION_ALLOW ], [ call.source, call.decision ]
  end

  test "it lists only the two web tools, and an ended session reaches nothing" do
    post "/code_agent/tools", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json, headers: { "Authorization" => "Bearer #{@token}", "CONTENT_TYPE" => "application/json" }
    assert_equal %w[search_web read_web_page], response.parsed_body.dig("result", "tools").map { |tool| tool["name"] }

    @session.close!
    post "/code_agent/tools", params: { jsonrpc: "2.0", id: 2, method: "tools/list" }.to_json, headers: { "Authorization" => "Bearer #{@token}" }
    assert_response :unauthorized
  end

  test "a session's lookups are capped, and a workspace that switched web search off offers none" do
    @session.update_columns(web_lookups: CodeAgentSession::MAX_WEB_LOOKUPS)
    WebLookup.expects(:search).never

    post "/code_agent/tools", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "search_web", arguments: { query: "x" } } }.to_json,
                              headers: { "Authorization" => "Bearer #{@token}", "CONTENT_TYPE" => "application/json" }
    assert_equal CodeAgentSession::TOO_MANY_LOOKUPS, response.parsed_body.dig("result", "content", 0, "text")

    @workspace.update!(web_search_enabled: false)
    post "/code_agent/tools", params: { jsonrpc: "2.0", id: 2, method: "tools/list" }.to_json, headers: { "Authorization" => "Bearer #{@token}", "CONTENT_TYPE" => "application/json" }
    assert_empty response.parsed_body.dig("result", "tools")
    get "/code_agent/tools"
    assert_response :method_not_allowed
  end
end
