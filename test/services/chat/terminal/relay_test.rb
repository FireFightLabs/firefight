require "test_helper"

class Chat::Terminal::RelayTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    @conversation.chat_record
    @turn = Conversation::Turn.new(@conversation, asker: @member)

    fake = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "fake", name: "Fake")
    fake.integration_environments.create!(credentials: { token: "x" }.to_json)
    @reads = fake.tools.create!(name: "echo_text", description: "Echoes text back", params_schema: { "type" => "object" }, enabled: true, read_only: true)
    @writes = fake.tools.create!(name: "write_thing", description: "Writes a thing", params_schema: { "type" => "object" }, enabled: true, read_only: false)
    Ability::Grant.create!(workspace: @workspace, principal: @member, action: @writes.reload.ability_action)
    Integrations::NativePack.stubs(:for).with("fake").returns(FakeNativePack)
    Chat::Terminal.stubs(:relay_base).returns("https://ff.example/sandbox_relay")
  end

  test "a command reads a connected tool through Firefight, as the person, and the activity log holds the call" do
    said = relay(changes: false).call(@reads.model_facing_name, "text" => "hello")

    assert_equal [ Chat::Terminal::Relay::OUTCOME_OK, "echo: hello" ], [ said.outcome, said.text ]
    invocation = Ability::Invocation.find_by!(workspace: @workspace, action_key: @reads.action_key)
    assert_equal [ Ability::Invocation::DECISION_ALLOW, @member, AbilityGateway::SOURCE_CONVERSATION ],
                 [ invocation.decision, invocation.principal, invocation.source ]
  end

  test "a change is refused unless the person confirmed the command as one, and runs once they did" do
    refused = relay(changes: false).call(@writes.model_facing_name, {})

    assert_equal Chat::Terminal::Relay::OUTCOME_REFUSED, refused.outcome
    assert_match "did not confirm this command as a change", refused.text
    assert_not Ability::Invocation.exists?(workspace: @workspace, action_key: @writes.action_key)

    allowed = relay(changes: true).call(@writes.model_facing_name, {})
    assert_equal [ Chat::Terminal::Relay::OUTCOME_OK, "written" ], [ allowed.outcome, allowed.text ]
  end

  test "a confirmed command still never makes a change with a safeguard of its own, which Halon calls itself" do
    Integrations::Effects.stubs(:of).returns([])
    Integrations::Effects.stubs(:of).with(@writes).returns([ Ability::Action::EFFECT_STOPS ])

    said = relay(changes: true).call(@writes.model_facing_name, {})

    assert_equal Chat::Terminal::Relay::OUTCOME_REFUSED, said.outcome
    assert_match "Call it yourself", said.text
    assert_match "whoever started it is asked first", said.text
    assert_not Ability::Invocation.exists?(workspace: @workspace, action_key: @writes.action_key)
  end

  test "kubectl reads a cluster through the general read, with the API's own answer" do
    kubernetes = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "kubernetes", name: "Kubernetes")
    kubernetes.integration_environments.create!(credentials: { token: "x" }.to_json)
    read = kubernetes.tools.create!(name: Integrations::ApiReads::TOOL, description: "Reads the API", enabled: true, read_only: true,
                                    params_schema: { "type" => "object" })
    Integrations::NativeExecutor.expects(:call).with { |tool:, arguments:, relayed:, **| tool == read && relayed && arguments == { "path" => "/api/v1/namespaces/default/pods", "query" => { "limit" => "500" } } }
                                .returns("content" => [ { "type" => "text", "text" => "Kubernetes answered." } ],
                                         Integrations::Telemetry::STRUCTURED => { Integrations::Telemetry::RELAYED => { "kind" => "PodList", "items" => [] } })

    answered = relay(changes: false).api(kubernetes.slug, "GET", "api/v1/namespaces/default/pods", { "limit" => "500" }, nil)
    refused = relay(changes: false).api(kubernetes.slug, "DELETE", "api/v1/namespaces/default/pods/web-1", {}, nil)

    assert_equal [ 200, { "kind" => "PodList", "items" => [] } ], [ answered.status, answered.body ]
    assert_equal 403, refused.status
    assert_match "only reads", refused.body.dig("error", "message")
  end

  test "a change an approval rule holds waits, and the chat keeps it for the person to run once approved" do
    @workspace.find_or_create_approval_policy!.policy_rules.create!(priority: 1, conditions: [], outcome: { "require" => { "role" => "admin", "count" => 1 } })

    said = relay(changes: true).call(@writes.model_facing_name, {})

    assert_equal Chat::Terminal::Relay::OUTCOME_WAITING, said.outcome
    assert_match Chat::Tools::WAITING, said.text
    assert Chat::HeldCall.exists?(chat: @conversation.chat_record)
  end

  test "an investigation's command reads as the investigator and never changes anything" do
    investigation = @workspace.investigations.create!(subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
                                                      max_turns: 10, max_spend_cents: 400)
    Ability::Grant.create!(workspace: @workspace, principal: SystemAgent.investigator, action: @reads.reload.ability_action)
    session, = Chat::TerminalSession.open!(investigation, changes: true, lasts: 60.seconds)
    relay = Chat::Terminal::Relay.new(session)

    assert_equal "echo: hi", relay.call(@reads.model_facing_name, "text" => "hi").text
    assert_equal 1, investigation.steps.where(action_key: @reads.action_key).count
    assert_equal [], relay.tools.map { |tool| tool["name"] } & [ @writes.model_facing_name ]
  end

  test "the tools a command may call are listed with whether they read, and Firefight's own changes are left out" do
    listed = relay(changes: false).tools("echo")

    assert_equal [ { "name" => @reads.model_facing_name, "reads" => true, "description" => "Echoes text back" } ], listed
    names = relay(changes: true).tools.map { |tool| tool["name"] }
    assert_includes names, @writes.model_facing_name
    assert_not_includes names, Mcp::Tools::DECLARE_INCIDENT
  end

  test "a command can make only so many calls, and none once it ended" do
    session, = Chat::TerminalSession.open!(@turn, changes: false, lasts: 60.seconds)
    Chat::TerminalSession.where(id: session.id).update_all(calls: Chat::TerminalSession::MAX_CALLS)

    assert_equal Chat::TerminalSession::TOO_MANY, Chat::Terminal::Relay.new(session.reload).call(@reads.model_facing_name, {}).text
    assert_equal Chat::TerminalSession::ENDED, Chat::Terminal::Relay.new(nil, agent_run: @turn).call(@reads.model_facing_name, {}).text
  end

  test "a provider's own command line tool reaches its connection's API inside a project, with the API's own answer" do
    api = northflank_api
    Integrations::NativeExecutor.expects(:call).with do |tool:, arguments:, relayed:, **|
      tool == api && relayed && arguments == { "method" => "GET", "path" => "services/web", "project" => "shop", "query" => { "per_page" => "5" } }
    end.returns("content" => [ { "type" => "text", "text" => "Northflank answered GET services/web." } ],
                Integrations::Telemetry::STRUCTURED => { Integrations::Telemetry::RELAYED => { "data" => { "id" => "web" } } })

    answered = relay(changes: false).api(api.integration.slug, "GET", "v1/projects/shop/services/web", { "per_page" => "5" }, nil)

    assert_equal [ 200, { "data" => { "id" => "web" } } ], [ answered.status, answered.body ]
  end

  test "a provider command line tool's change is refused unless confirmed, and a call outside a project is refused in words" do
    api = northflank_api
    Integrations::NativeExecutor.expects(:call).never

    refused = relay(changes: false).api(api.integration.slug, "POST", "v1/projects/shop/services/web/restart", {}, {})
    assert_equal 403, refused.status
    assert_match "did not confirm this command as a change", refused.body.dig("error", "message")

    outside = relay(changes: false).api(api.integration.slug, "GET", "v1/projects", {}, nil)
    assert_equal 403, outside.status
    assert_match "inside a project", outside.body.dig("error", "message")
  end

  test "each connection with a command line tool is handed out pointed at the relay" do
    api = northflank_api

    offered = relay(changes: false).clis("tok")

    assert_equal [ [ api.integration.slug, "northflank" ] ], offered.map { |cli| [ cli.connection, cli.command ] }
    assert_equal({ "NF_API_BASE_URL" => "https://ff.example/sandbox_relay/api/#{api.integration.slug}", "NF_API_TOKEN" => "tok" }, offered.first.env)
  end

  private

  def relay(changes:)
    session, = Chat::TerminalSession.open!(@turn, changes: changes, lasts: 60.seconds)
    Chat::Terminal::Relay.new(session)
  end

  def northflank_api
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank")
    northflank.integration_environments.create!(credentials: { token: "x" }.to_json).store_fields!("project" => "shop")
    api = northflank.tools.create!(name: "api_request", description: "Calls the API", enabled: true, read_only: false,
                                   params_schema: { "type" => "object", "properties" => { "method" => { "type" => "string" }, "path" => { "type" => "string" } } })
    Ability::Grant.create!(workspace: @workspace, principal: @member, action: api.reload.ability_action)
    api
  end
end
