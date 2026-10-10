require "test_helper"

# A workspace with two Northflank connections, each reaching its own project. In a real chat the second one's tools were
# switched on while the chat went on, Halon kept calling the first one's api_request from what it remembered, and asked
# the person to confirm "Scale Faylee's web to 0" through a card titled "Northflank api request", which scaled the first
# project instead. These replay that chat's shape.
class Chat::Tools::ConnectionTargetingTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    @turn = Conversation::Turn.new(@conversation, asker: workspace_memberships(:alice_workspace_one))
    @chat = @conversation.chat_record

    @firefight, @firefight_row = connection!("Northflank", "firefight", enabled: true)
    @faylee, @faylee_row = connection!("Faylee", "faylee", enabled: false)
    @firefight_web = resource!(@firefight_row, "uros-team/firefight")
    @faylee_web = resource!(@faylee_row, "uros-team/faylee")
  end

  test "the connection is told apart by the name it was given and the provider, with the project it reaches" do
    assert_equal "Faylee (Northflank)", @faylee.display_name
    assert_equal "Northflank", @firefight.display_name
    assert_equal "Faylee (Northflank), project faylee", @faylee.target_label
    assert_equal "Northflank, project firefight", @firefight.target_label
  end

  test "the tool behind each step of a chat is looked up once per workspace, switched on or not" do
    workspace = Workspace.find(@workspace.id)
    assert_equal "northflank_api_request", Chat::Tools::Target.connection_tool(workspace, "northflank_api_request").model_facing_name
    faylee_tool = @faylee.tools.first.model_facing_name
    assert_queries_count(0) do
      assert_equal faylee_tool, Chat::Tools::Target.connection_tool(workspace, faylee_tool).model_facing_name
      assert_nil Chat::Tools::Target.connection_tool(workspace, "remember")
    end
  end

  test "a connection with every tool off is named when its group is opened, though the other connection's tools are on" do
    open = Chat::Tools::Open.new(@turn, offer: ->(_tools) { })

    opened = open.call(group: cloud_group)

    assert_match "northflank_api_request", opened
    assert_match "Faylee (Northflank) is connected, but none of its tools are switched on. An admin can switch them on in Integrations.", opened
    assert_match "though Faylee (Northflank) has no tools switched on", open.description
  end

  test "loading a provider's skill names the connection that has the skill's tools switched off" do
    loaded = Chat::Tools::UseSkill.new(@turn, offer: ->(_tools) { }).call(skill: "northflank_fixes")

    assert_match "Faylee (Northflank) is connected, but none of its tools are switched on, so no step reaches project faylee.", loaded

    @faylee.tools.find_by!(name: "list_resources").update!(enabled: true)
    loaded = Chat::Tools::UseSkill.new(@turn, offer: ->(_tools) { }).call(skill: "northflank_fixes")
    assert_match "Faylee (Northflank) has api_request switched off, so a step that needs it cannot reach project faylee through it.", loaded
  end

  test "tools switched on mid chat are told to Halon, offered at once, and tools that are gone are forgotten" do
    @chat.update!(found_tool_names: %w[northflank_api_request northflank_list_resources gone_tool])
    assert_nil Chat::Tools::Changes.catch_up!(@turn, @chat).note, "a chat that never looked is only recorded"

    @faylee.tools.each { |tool| tool.update!(enabled: true) }
    caught = Chat::Tools::Changes.catch_up!(@turn, @chat.reload)

    assert_match "Faylee (Northflank) had faylee_api_request and faylee_list_resources switched on.", caught.note
    assert_match "open #{cloud_group} again with open_tools", caught.note
    assert_equal %w[faylee_api_request faylee_list_resources], caught.offered.map(&:name).sort
    assert_equal %w[northflank_api_request northflank_list_resources faylee_api_request faylee_list_resources], @chat.reload.found_tool_names
    assert_equal %w[faylee_api_request faylee_list_resources northflank_api_request northflank_list_resources],
                 Chat::Tools.known(@turn, @chat).map(&:name).sort
    assert_nil Chat::Tools::Changes.catch_up!(@turn, @chat.reload).note, "a change is told once"
  end

  test "a connection added, renamed, pointed elsewhere, switched off or removed is told too" do
    Chat::Tools::Changes.catch_up!(@turn, @chat)
    other, = connection!("Billing", "billing", enabled: false)
    @faylee.update!(name: "Faylee Prod")
    @faylee_row.store_fields!("project" => "faylee-prod")
    @firefight.update!(disabled_at: Time.current)

    note = Chat::Tools::Changes.catch_up!(@turn, @chat.reload).note

    assert_match "Billing (Northflank) was connected, reaching project billing, with none of its tools switched on yet.", note
    assert_match "Faylee (Northflank) is now called Faylee Prod (Northflank).", note
    assert_match "Faylee Prod (Northflank) now reaches project faylee-prod.", note
    assert_match "Northflank was switched off, so none of its tools can be used.", note

    other.update!(deleted_at: Time.current)
    assert_match "Billing (Northflank) was removed, so its tools are gone.", Chat::Tools::Changes.catch_up!(@turn, @chat.reload).note
  end

  test "a call to one connection's tool whose words name the other is refused before anyone is asked" do
    @faylee.tools.each { |tool| tool.update!(enabled: true) }
    tool = connection_tool("northflank_api_request")
    Integrations::NativeExecutor.expects(:call).never
    arguments = { "method" => "POST", "path" => "services/web/scale", "body" => { "instances" => 0 },
                  "intent" => "Scale Faylee's web service to zero instances as requested." }

    assert tool.requires_approval?
    assert_equal true, tool.approval_resolver.call(RubyLLM::ToolCall.new(id: "call_1", name: tool.name, arguments: arguments)),
                 "a refused call runs at once, so it is never put to the person"
    refused = tool.call(tool_call: RubyLLM::ToolCall.new(id: "call_1", name: tool.name, arguments: arguments), **arguments.symbolize_keys)

    assert_match "Not run, and nobody was asked. northflank_api_request reaches Northflank, project firefight, but what you wrote names Faylee (Northflank).", refused
    assert_match "To reach Faylee (Northflank), project faylee, call faylee_api_request", refused
  end

  test "when the other connection's tool is off, the refusal says so rather than pointing at it" do
    refused = connection_tool("northflank_api_request").call(method: "POST", path: "services/web/scale", intent: "Scale faylee web to 0")

    assert_match "Faylee (Northflank)'s api_request tool is switched off", refused
  end

  # A real release chat waited 38 minutes for the person to confirm a GET.
  test "a GET through api_request runs without asking, is shown as a read, and a change through it still asks" do
    tool = connection_tool("northflank_api_request")
    read = { "method" => "GET", "path" => "services/web", "intent" => "Read web's state" }
    change = { "method" => "POST", "path" => "services/web/restart", "intent" => "Restart web" }

    assert tool.requires_approval?
    assert_equal true, tool.approval_resolver.call(RubyLLM::ToolCall.new(id: "call_read", name: tool.name, arguments: read))
    assert_nil tool.approval_resolver.call(RubyLLM::ToolCall.new(id: "call_change", name: tool.name, arguments: change))
    assert_equal Chat::Tools::KIND_READ, Chat::Tools.kind(tool.name, @workspace, read)
    assert_equal Chat::Tools::KIND_ACT, Chat::Tools.kind(tool.name, @workspace, change)
  end

  test "words that name this connection's own project, or none, are put to the person as usual" do
    tool = connection_tool("northflank_api_request")
    call = RubyLLM::ToolCall.new(id: "call_2", name: tool.name, arguments: { "intent" => "Restore Firefight's web, which was scaled instead of Faylee's" })

    assert_nil tool.approval_resolver.call(call)
    assert_nil tool.approval_resolver.call(RubyLLM::ToolCall.new(id: "call_3", name: tool.name, arguments: { "intent" => "Scale web to zero" }))
  end

  test "a step through a connection is titled by the call and the connection, wherever steps are listed" do
    assert_equal "Api request · Faylee (Northflank)", Chat::Tools.step("faylee_api_request", {}, workspace: @workspace).title
    assert_equal "Api request · Northflank", Chat::Tools.step("northflank_api_request", {}, workspace: @workspace).title
    assert_equal "Scale", Chat::Tools.step("scale", {}, workspace: @workspace).title
    assert_equal "Get incident", Chat::Tools.step("get_incident", {}, workspace: @workspace).title

    message = @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    message.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: "faylee_api_request", arguments: { "path" => "services/web/scale" })
    assert_equal [ "Api request · Faylee (Northflank)" ], AgentChatMessageSerializer.one(message)[:tools].map { |step| step[:title] }
  end

  test "the question for the right tool names what it reaches, from the tool, and the call after it" do
    @faylee.tools.each { |tool| tool.update!(enabled: true) }
    call = pause_on("faylee_api_request", { "method" => "POST", "path" => "services/web/scale", "intent" => "Scale Faylee's web to 0" })

    Chat::Tools::Target.record!(@turn, [ call ])
    confirmation = Chat::Tools.confirmation(call.reload)

    assert_equal "Faylee (Northflank), project faylee", confirmation.target
    assert_equal "Api request", confirmation.call
    assert_equal "Api request on Faylee (Northflank), project faylee?", confirmation.question
    assert_equal "Scale Faylee's web to 0", confirmation.intent
  end

  test "RubyLLM puts only the call that reaches what it says to the person" do
    @faylee.tools.each { |tool| tool.update!(enabled: true) }
    wrong = pause_on("northflank_api_request", { "path" => "services/web/scale", "intent" => "Scale Faylee's web to 0" }, id: "call_wrong")
    right = pause_on("faylee_api_request", { "path" => "services/web/scale", "intent" => "Scale Faylee's web to 0" }, id: "call_right",
                                           message: wrong.message)
    RubyLLM.config.stubs(:openai_api_key).returns("not-used")
    llm = @chat.to_llm
    llm.with_tools(*Chat::Tools.catalog(@turn).filter_map(&:tool))

    assert_equal [ right.tool_call_id ], llm.pending_approvals.map(&:id)
  end

  test "a confirmed call that now reaches something else than the person was shown is not run" do
    @faylee.tools.each { |tool| tool.update!(enabled: true) }
    call = pause_on("faylee_api_request", { "path" => "services/web/scale" })
    call.update_columns(target: "Faylee (Northflank), project faylee-old", approval: Chat::APPROVAL_APPROVED)
    Integrations::NativeExecutor.expects(:call).never

    answer = connection_tool("faylee_api_request").call(tool_call: RubyLLM::ToolCall.new(id: call.tool_call_id, name: call.name, arguments: {}),
                                                        path: "services/web/scale")

    assert_match "The person confirmed this for Faylee (Northflank), project faylee-old, but it now reaches Faylee (Northflank), project faylee", answer
  end

  test "a capability takes a resource by its map id, and the connection holding it is a choice even with its tools off" do
    found = Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::SCALE, { "resource" => @firefight_web.id, "instances" => 0 },
                                               principal: workspace_memberships(:alice_workspace_one))
    assert_equal @firefight_row, found.environment_row

    scale = Chat::Tools.catalog(@turn).find { |entry| entry.name == "scale" }.tool
    assert_equal %w[northflank faylee], scale.parameters_schema.dig("properties", "connection", "enum")
    error = assert_raises(Integrations::Capabilities::Unroutable) do
      Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::SCALE, { "resource" => @faylee_web.id, "instances" => 0 },
                                         principal: workspace_memberships(:alice_workspace_one))
    end
    assert_match "Faylee would answer this with its api_request tool, which is switched off.", error.message
  end

  test "a scale whose words name the other connection is refused before anyone is asked" do
    scale = Chat::Tools.catalog(@turn).find { |entry| entry.name == "scale" }.tool
    arguments = { "resource" => @firefight_web.id, "instances" => 0, "intent" => "Scale Faylee's web to 0" }
    Integrations::NativeExecutor.expects(:call).never

    assert_equal true, scale.approval_resolver.call(RubyLLM::ToolCall.new(id: "call_9", name: "scale", arguments: arguments))
    assert_match "but what you wrote names Faylee (Northflank)", scale.call(**arguments.symbolize_keys)
    assert_equal "service web on Northflank, project firefight", Chat::Tools::Target.describe(@turn, "scale", arguments)
  end

  test "two resources of one name list each one's map id and connection" do
    error = assert_raises(Integrations::Capabilities::Unroutable) do
      Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::STATUS, { "resource" => "web" }, principal: workspace_memberships(:alice_workspace_one))
    end

    assert_match "map id #{@faylee_web.id}, on Faylee (Northflank)", error.message
    assert_match "map id #{@firefight_web.id}, on Northflank", error.message
  end

  private

  def connection!(name, project, enabled:)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: name)
    row = integration.integration_environments.create!(credentials: { token: "x" }.to_json)
    row.store_fields!("project" => project)
    %w[api_request list_resources].each do |tool|
      integration.tools.create!(name: tool, description: tool, read_only: tool != "api_request", enabled: enabled,
                                params_schema: { "type" => "object", "properties" => { "method" => {}, "path" => {}, "body" => {} } })
    end
    [ integration, row ]
  end

  def resource!(row, account)
    ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: account, kind: ResourceMap::KIND_SERVICE, external_id: "web",
                                  name: "web", integration_environment: row, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  def cloud_group = Chat::Tools::Groups.of_connection(@firefight)

  def connection_tool(name) = Chat::Tools.catalog(@turn).find { |entry| entry.name == name }.tool

  def pause_on(name, arguments, id: "call_1", message: nil)
    message ||= @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    call = message.ruby_llm_tool_calls.create!(tool_call_id: id, name: name, arguments: arguments)
    @chat.request_decisions!([ id ])
    call.reload
  end
end
