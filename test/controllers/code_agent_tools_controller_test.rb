require "test_helper"

class CodeAgentToolsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    @session, @token = open_session(@member)
    @integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "fake", name: "Fake")
    @integration.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { token: "x" }.to_json)
    @read = @integration.tools.create!(name: "echo_text", description: "Echoes text back", read_only: true, enabled: true,
                                       params_schema: { "type" => "object", "properties" => { "text" => { "type" => "string" } } })
    @write = @integration.tools.create!(name: "write_thing", description: "Writes a thing", read_only: false, enabled: true, params_schema: { "type" => "object" })
    Integrations::NativePack.stubs(:for).with("fake").returns(FakeNativePack)
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

  test "it lists the web tools and Halon's read tools, a question only where the change can be seen, and an ended session reaches nothing" do
    call("tools/list")
    assert_equal %w[search_web read_web_page list_tools describe_tool call_tool list_skills read_skill search_docs read_doc], tool_names

    placed, placed_token = open_session(@member, place: @workspace.conversations.create!(kind: Conversation::KIND_PERSONAL, started_by: @member, max_turns: 10, max_spend_cents: 50))
    call("tools/list", token: placed_token)
    assert_includes tool_names, CodeAgent::QuestionTools::ASK
    assert_includes tool_names, CodeAgent::QuestionTools::WAIT
    placed.close!

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
    call("tools/list")
    assert_equal %w[list_tools describe_tool call_tool list_skills read_skill search_docs read_doc], tool_names
    get "/code_agent/tools"
    assert_response :method_not_allowed
  end

  test "a read tool runs as the person who asked, through the gateway, in Activity under the coding agent, and a tool that changes things is never offered" do
    call("tools/call", name: CodeAgent::ReadTools::LIST)
    listed = text
    assert_includes listed, "fake_echo_text: Echoes text back"
    refute_includes listed, "fake_write_thing", "a tool that changes something is never handed to the coding agent"

    call("tools/call", name: CodeAgent::ReadTools::CALL, arguments: { name: "fake_echo_text", arguments: { text: "hi" } })
    assert_includes text, "echo: hi"
    assert_includes text, "trust=\"untrusted\"", "what a tool returns is framed as evidence"
    invocation = Ability::Invocation.find_by!(workspace: @workspace, action_key: @read.action_key)
    assert_equal [ AbilityGateway::SOURCE_CODE_AGENT, @member, "Coding agent for acme/api" ],
                 [ invocation.source, invocation.principal, invocation.triggered_by_label ]

    call("tools/call", name: CodeAgent::ReadTools::CALL, arguments: { name: "fake_write_thing", arguments: {} })
    assert response.parsed_body.dig("result", "isError")
    assert_includes text, "There is no tool called fake_write_thing that you may read with."
    assert_equal 0, Ability::Invocation.where(workspace: @workspace, action_key: @write.action_key).count
    assert_equal 1, @session.reload.tool_calls
  end

  test "an agent principal without a grant reads nothing through the bridge, as it reaches nothing anywhere else" do
    agent = @workspace.agents.create!(name: "Release bot", slug: "release_bot")
    _, token = open_session(agent)

    call("tools/call", token: token, name: CodeAgent::ReadTools::LIST)
    refute_includes text, "fake_echo_text"

    call("tools/call", token: token, name: CodeAgent::ReadTools::CALL, arguments: { name: "fake_echo_text", arguments: { text: "hi" } })
    assert response.parsed_body.dig("result", "isError")
    assert_equal 0, Ability::Invocation.where(workspace: @workspace, action_key: @read.action_key, decision: Ability::Invocation::DECISION_ALLOW).count
  end

  test "the coding agent searches the docs store before the web, finding a page by its exact name and by a question in other words" do
    store_doc_page(provider: "northflank", path: "docs/application/release/run-and-manage-workflows.md",
                   url: "https://northflank.com/docs/v1/application/release/run-and-manage-workflows.md", content: <<~MARKDOWN)
                     # Run and manage workflows

                     ## Run a workflow using a webhook

                     Treat the URL as a credential.

                     ### Git trigger parameters

                     Pass `release.sha` and `release.branch` as query parameters on the webhook URL.
                   MARKDOWN
    store_doc_page(provider: "render", path: "deploy/hooks.md", content: "# Deploy hooks\n\nA deploy hook starts a deploy.")
    @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "northflank", name: "Northflank")
    FirefightAi.stubs(:embed).raises(FirefightAi::TerminalError.new("no key", reason: "ConfigurationError"))

    call("tools/list")
    assert_match "before the web", response.parsed_body.dig("result", "tools").find { |tool| tool["name"] == Chat::Tools::Docs::SEARCH }["description"]

    call("tools/call", name: Chat::Tools::Docs::SEARCH, arguments: { query: "release.sha" })
    assert text.start_with?(Chat::Tools::Docs::NOTE), "it is the provider's text, framed as data"
    assert_includes text, %(<tool_result tool="search_docs" trust="untrusted">)
    assert_includes text, "page docs/application/release/run-and-manage-workflows.md"

    call("tools/call", name: Chat::Tools::Docs::SEARCH, arguments: { query: "how do I hand the commit to a workflow webhook trigger" })
    assert_includes text, "Northflank: Run and manage workflows > Run a workflow using a webhook"
    assert_not_includes text, "Deploy hooks", "only the connected providers unless one is named"

    call("tools/call", name: Chat::Tools::Docs::READ,
                       arguments: { provider: "northflank", page: "docs/application/release/run-and-manage-workflows.md", section: "Git trigger parameters" })
    assert_includes text, "release.branch"
    assert_equal 3, @session.reload.tool_calls, "each docs call counts against the change's limit"

    @session.update_columns(tool_calls: CodeAgentSession::MAX_TOOL_CALLS)
    call("tools/call", name: Chat::Tools::Docs::SEARCH, arguments: { query: "release.sha" })
    assert_equal CodeAgentSession::TOO_MANY_TOOL_CALLS, text
  end

  test "a session's read tool calls are capped" do
    @session.update_columns(tool_calls: CodeAgentSession::MAX_TOOL_CALLS)

    call("tools/call", name: CodeAgent::ReadTools::CALL, arguments: { name: "fake_echo_text", arguments: { text: "hi" } })

    assert_equal CodeAgentSession::TOO_MANY_TOOL_CALLS, text
  end

  test "the coding agent starts a database in its own sandbox, ledgered under the workspace, and one the sandbox cannot start is said plainly" do
    boxed, boxed_token = open_session(@member)
    boxed.update_columns(box_key: "conversation-7")
    CodeBox.create!(workspace: @workspace, key: "conversation-7", provider: "docker", box_ref: "box-1", address: "http://127.0.0.1:9", secret: "k", last_used_at: Time.current)
    Integrations::Sandboxes::Client.any_instance.expects(:start_services).with([ "postgres" ])
                                   .returns("env" => { "DATABASE_URL" => "postgres://runner@127.0.0.1:5432/postgres" }, "started" => [ "postgres" ])

    call("tools/list", token: boxed_token)
    assert_includes tool_names, CodeAgent::SandboxTools::START
    call("tools/call", token: boxed_token, name: CodeAgent::SandboxTools::START, arguments: { name: "Postgres" })

    assert_equal "postgres is running in this sandbox. Set these on the command that uses it:\nDATABASE_URL=postgres://runner@127.0.0.1:5432/postgres", text
    started = Ability::Invocation.find_by!(workspace: @workspace, action_key: Ability::Action::SANDBOX_SERVICE)
    assert_equal [ AbilityGateway::SOURCE_CODE_AGENT, Ability::Invocation::DECISION_ALLOW, "Coding agent for acme/api" ],
                 [ started.source, started.decision, started.triggered_by_label ]

    call("tools/call", token: boxed_token, name: CodeAgent::SandboxTools::START, arguments: { name: "mysql" })

    assert_equal "The sandbox cannot start mysql. It can start postgres and redis.", text
    assert response.parsed_body.dig("result", "isError")
    assert_equal 1, Ability::Invocation.where(workspace: @workspace, action_key: Ability::Action::SANDBOX_SERVICE).count
  end

  test "a change whose sandbox stopped is told nothing started" do
    boxed, boxed_token = open_session(@member)
    boxed.update_columns(box_key: "conversation-8")

    call("tools/call", token: boxed_token, name: CodeAgent::SandboxTools::START, arguments: { name: "redis" })

    assert_equal "redis could not start: The sandbox for this change is not running, so nothing was started.", text
  end

  private

  def open_session(principal, place: nil)
    request = CodeAgent::Request.new(principal: principal, source: AbilityGateway::SOURCE_CONVERSATION, place: place)
    CodeAgentSession.open!(workspace: @workspace, choice: FirefightAi::ModelChoice.new(model: "gpt-4o", provider: "openai"), repository: "acme/api",
                           request: request)
  end

  def call(method, token: @token, **params)
    body = { jsonrpc: "2.0", id: 1, method: method }
    body[:params] = params if params.any?
    post "/code_agent/tools", params: body.to_json, headers: { "Authorization" => "Bearer #{token}", "CONTENT_TYPE" => "application/json" }
  end

  def tool_names = response.parsed_body.dig("result", "tools").map { |tool| tool["name"] }

  def text = response.parsed_body.dig("result", "content", 0, "text").to_s
end
