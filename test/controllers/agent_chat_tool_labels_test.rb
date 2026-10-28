require "test_helper"

# A chat's steps name the connection tool each called and say whether it only read. The page reads a few columns of the
# workspace's tools for that, once, and keeps them cached until a connection or a tool changes.
class AgentChatToolLabelsTest < ActionDispatch::IntegrationTest
  # A read of the tools' own rows, not the one query that dates every connection and tool (Workspace#reach_version).
  TOOL_ROWS = /\ASELECT .*FROM "integration_tools"/

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    sign_in(users(:alice), @workspace)
    @connection = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Shop", slug: "shop")
    @connection.integration_environments.create!(credentials: { token: "x" }.to_json)
    @reader = @connection.tools.create!(name: "list_services", description: "Lists", read_only: true, enabled: true,
                                        params_schema: { "type" => "object", "properties" => { "filter" => { "type" => "string", "description" => "x" * 4000 } } })
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    @conversation.ask!("What runs?")
    asking = @conversation.chat_record.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    call = asking.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: @reader.model_facing_name, arguments: {})
    call.update!(result: @conversation.chat_record.messages.create!(role: Chat::Message::ROLE_TOOL, content: "web, api"))
    vercel = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "vercel", name: "Sites", slug: "sites")
    vercel.integration_environments.create!(credentials: { token: "x" }.to_json)
    scoped = vercel.tools.create!(name: "list_projects", description: "Lists", read_only: true, enabled: true, params_schema: { "type" => "object" })
    # A call that names one team of several is titled with it, from the connection's own words.
    named = asking.ruby_llm_tool_calls.create!(tool_call_id: "call_2", name: scoped.model_facing_name, arguments: { "team" => "acme" })
    named.update!(result: @conversation.chat_record.messages.create!(role: Chat::Message::ROLE_TOOL, content: "shop"))
    @conversation.reply_delivered!
  end

  test "the page reads the tools' labels in one slim query, then from the cache, on one workspace" do
    cold = thread
    warm = thread

    tool_reads = cold.grep(TOOL_ROWS)
    assert_equal 1, tool_reads.size, tool_reads.join("\n")
    assert_no_match(/params_schema|description|"spec"|integration_environments|ability_actions/, tool_reads.sole)
    assert_empty warm.grep(TOOL_ROWS), "a step naming one team of several reads no tool whole either"
    titled = inertia_props[AgentChatsController::PROP_MESSAGES].flat_map { |message| message["tools"] }.find { |step| step["key"] == "call_2" }
    assert_match "acme", titled["title"]
    page = queries_sent { get agent_chat_url(@conversation), headers: inertia_headers }
    [ cold, warm, page ].each do |queries|
      assert_equal 1, queries.grep(/FROM "workspaces" WHERE "workspaces"."id"/).size, "each request holds one workspace"
    end
  end

  test "a tool switched off, or a connection renamed, shows on the next view" do
    assert_equal [ "List services · Shop (Northflank)", Chat::Tools::KIND_READ ], shown_step

    @reader.update!(enabled: false)
    assert_equal Chat::Tools::KIND_ACT, shown_step.last

    @connection.update!(name: "Storefront")
    assert_equal "List services · Storefront (Northflank)", shown_step.first
  end

  private

  def thread
    queries_sent { get agent_chat_url(@conversation), headers: inertia_partial_headers("agent/index", AgentChatsController::THREAD_PROPS) }
  end

  def shown_step
    thread
    step = inertia_props[AgentChatsController::PROP_MESSAGES].flat_map { |message| message["tools"] }.find { |each| each["key"] == "call_1" }
    step.values_at("title", "kind")
  end
end
