require "test_helper"

# Look before you change. A change in a chat names the reads that show it will help, from this turn or from Halon's
# previous answer while they are fresh, Firefight checks them against the reads Halon made, and a change with none goes
# back to Halon before anyone is asked.
class Chat::Tools::LookFirstTest < ActiveSupport::TestCase
  BOUNCED = "#{Chat::Tools::LookFirst::BOUNCE} #{Chat::Tools::LookFirst::STUCK}".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    @turn = Conversation::Turn.new(@conversation, asker: @member)
    @chat = @conversation.chat_record

    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    row = northflank.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { token: "x" }.to_json)
    %w[search_logs list_containers api_request].each do |name|
      northflank.tools.create!(name: name, description: name, read_only: name != "api_request", enabled: true, params_schema: { "type" => "object" })
    end
    ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "team/prod", kind: ResourceMap::KIND_SERVICE, external_id: "web-id",
                                  name: "web", integration_environment: row, first_seen_at: Time.current, last_seen_at: Time.current)

    fake = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "fake", name: "Fake")
    fake.integration_environments.create!(credentials: { token: "x" }.to_json)
    fake.tools.create!(name: "write_thing", description: "Writes", params_schema: { "type" => "object" }, enabled: true, read_only: false)
    Integrations::NativePack.stubs(:for).with("fake").returns(FakeNativePack)
    Chat.any_instance.stubs(:with_tools)
  end

  test "a restart with nothing read in this turn goes back to Halon before any card, and nothing runs" do
    asked!("web is erroring, restart it")
    call = change!("call_restart", "restart", "resource" => "web", "intent" => "Restart web")
    restart = tool("restart")
    Integrations::NativeExecutor.expects(:call).never

    assert restart.approval_resolver.call(call), "the call is sent back rather than put to the person"
    answer = restart.call(tool_call: call, "resource" => "web", "intent" => "Restart web")

    assert_equal BOUNCED, answer
    assert_equal [ true, Chat::StepOutcome::FAILURE_REFUSED ], @chat.tool_calls.where(tool_call_id: "call_restart").pick(:failed, :failure_kind)
    assert_not Ability::Invocation.exists?(workspace: @workspace, action_key: "northflank.api_request")
  end

  test "a read from an answer long ago does not back a change, and the one it names is said back" do
    because = [ "search_logs: 500s since 14:02" ]
    travel_to(30.minutes.ago) do
      asked!("how is web?")
      read!("call_old", "search_logs", { "resource" => "web" }, "500s since 14:02")
    end
    asked!("restart it then")
    call = change!("call_stale", "restart", "resource" => "web", "because" => because)
    Integrations::NativeExecutor.expects(:call).never
    answer = tool("restart").call(tool_call: call, "resource" => "web", "because" => because)
    assert_equal "#{Chat::Tools::LookFirst::BOUNCE} You named search_logs, which you did not read in this turn or recently enough. " \
                 "#{format(Chat::Tools::LookFirst::LOADED, reads: 'search_logs')} #{Chat::Tools::LookFirst::STUCK}", answer
    assert_includes @chat.reload.known_tool_names, "search_logs", "the read it named is handed to Halon for its next step"
  end

  test "approving what Halon proposed in its previous answer goes ahead on its reads while they are fresh" do
    because = [ "search_logs: 500s since 14:02" ]
    travel_to((Chat::Tools::LookFirst::PROPOSAL_FRESH_FOR - 2.minutes).ago) do
      asked!("how is web now?")
      read!("call_fresh", "search_logs", { "resource" => "web" }, "500s since 14:02")
    end
    asked!("yes, restart it")
    assert_nil Chat::Tools::LookFirst.refusal(@turn, { "because" => because }), "approving what Halon just proposed needs no second read"

    travel(Chat::Tools::LookFirst::PROPOSAL_FRESH_FOR) do
      assert_match Chat::Tools::LookFirst::BOUNCE, Chat::Tools::LookFirst.refusal(@turn, { "because" => because }), "past the limit Halon reads again"
    end
  end

  test "a read from two answers back never counts, however fresh" do
    because = [ "search_logs: 500s since 14:02" ]
    asked!("how is web?")
    read!("call_logs", "search_logs", { "resource" => "web" }, "500s since 14:02")
    asked!("and the database?")
    asked!("restart web")

    assert_match Chat::Tools::LookFirst::BOUNCE, Chat::Tools::LookFirst.refusal(@turn, { "because" => because })
  end

  test "a change naming a read from this turn is put to the person, and the card shows the read and what it showed" do
    asked!("web is erroring, restart it")
    read!("call_logs", "search_logs", { "resource" => "web" }, "500s since 14:02")
    because = [ "search_logs: 500s since 14:02, right after the deploy" ]
    call = change!("call_restart", "restart", "resource" => "web", "intent" => "Restart web", "because" => because)

    assert_nil tool("restart").approval_resolver.call(call), "the person is asked as before"

    @chat.request_decisions!([ "call_restart" ])
    confirmation = Chat::Tools.confirmation(@chat.tool_calls.find_by!(tool_call_id: "call_restart"))
    label = Chat::Tools.label("search_logs", { "resource" => "web" }, workspace: @workspace)
    assert_equal Chat::Tools::SUPPORT_LEAD, confirmation.support_lead
    assert_equal [ Chat::Tools::SupportPoint.new(text: "500s since 14:02, right after the deploy", source: label) ], confirmation.support_points
    text = Slack::Modals::AgentConfirmationDetails.build(confirmation).to_json
    assert_includes text, Chat::Tools::SUPPORT_LEAD
    assert_includes text, "500s since 14:02, right after the deploy"
    assert_equal [ { text: "500s since 14:02, right after the deploy", source: label } ],
                 AgentChatConfirmationSerializer.one(@chat.tool_calls.find_by!(tool_call_id: "call_restart"))[:supportPoints]
  end

  test "a change through a connection bounces without a read, and runs once it names one, while a read through the same tool never needs one" do
    asked!("write the thing")
    write = tool("fake_write_thing")
    bare = change!("call_bare", "fake_write_thing", {})
    Integrations::NativeExecutor.expects(:call).never

    assert write.approval_resolver.call(bare)
    assert_equal BOUNCED, write.call(tool_call: bare)

    read!("call_logs", "search_logs", { "resource" => "web" }, "the thing is missing")
    backed = change!("call_backed", "fake_write_thing", "because" => [ "search_logs" ])
    Integrations::NativeExecutor.unstub(:call)
    Integrations::NativeExecutor.expects(:call).with { |arguments:, **| !arguments.key?("because") }.returns("content" => [ { "type" => "text", "text" => "written" } ])

    assert_match "written", write.call(tool_call: backed, "because" => [ "search_logs" ])
  end

  test "a call the person already confirmed is never sent back after their answer" do
    asked!("restart web")
    call = change!("call_restart", "restart", "resource" => "web", "intent" => "Restart web")
    @chat.request_decisions!([ "call_restart" ])
    @chat.decide!("call_restart", approved: true)

    assert_nil Chat::Tools::LookFirst.refusal(@turn, {}, tool_call_id: call.id)
  end

  test "resolving, cancelling, deleting or revoking in Firefight needs a read, its small writes and its reads never do, and only a chat asks it" do
    asked!("resolve it")
    resolve = tool(Mcp::Tools::RESOLVE_INCIDENT)
    call = change!("call_resolve", Mcp::Tools::RESOLVE_INCIDENT, "incident" => "INC-1")

    assert_includes resolve.parameters_schema.deep_stringify_keys["required"], Chat::Tools::LookFirst::BECAUSE
    assert_equal BOUNCED, resolve.call(tool_call: call, "incident" => "INC-1")
    assert_includes tool(Mcp::Tools::DELETE_CATALOG_ENTRY).parameters_schema.deep_stringify_keys["required"], Chat::Tools::LookFirst::BECAUSE
    [ Mcp::Tools::COMPLETE_ACTION_ITEM, Mcp::Tools::POST_INCIDENT_UPDATE ].each do |name|
      assert_not tool(name).parameters_schema.to_h.deep_stringify_keys.fetch("properties", {}).key?(Chat::Tools::LookFirst::BECAUSE), name
    end
    assert_nil tool(Mcp::Tools::COMPLETE_ACTION_ITEM).send(:unsupported, { "action_item" => "AI-1" }, nil)
    assert_not tool(Mcp::Tools::GET_INCIDENT).parameters_schema.to_h.deep_stringify_keys.fetch("properties", {}).key?(Chat::Tools::LookFirst::BECAUSE)
    assert_not tool("search_logs").parameters_schema["properties"].key?(Chat::Tools::LookFirst::BECAUSE)
    assert_includes tool("restart").parameters_schema["required"], Chat::Tools::LookFirst::BECAUSE

    investigation = @workspace.investigations.create!(subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
                                                      max_turns: 5, max_spend_cents: 40)
    assert_not Chat::Tools::LookFirst.applies?(investigation)
    assert_not Chat::Tools::LookFirst.applies?(Conversation::Turn.new(@conversation, asker: @member, reads_only: true))
  end

  private

  def tool(name) = Chat::Tools.catalog(@turn).find { |entry| entry.name == name }.tool

  def asked!(words) = @chat.messages.create!(role: Chat::Message::ROLE_USER, content: words)

  def read!(tool_call_id, name, arguments, answer)
    message = @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    call = message.ruby_llm_tool_calls.create!(tool_call_id: tool_call_id, name: name, arguments: arguments)
    call.update!(result: @chat.messages.create!(role: Chat::Message::ROLE_TOOL, content: answer))
  end

  def change!(tool_call_id, name, arguments)
    message = @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    message.ruby_llm_tool_calls.create!(tool_call_id: tool_call_id, name: name, arguments: arguments)
    RubyLLM::ToolCall.new(id: tool_call_id, name: name, arguments: arguments)
  end
end
