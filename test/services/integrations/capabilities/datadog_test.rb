require "test_helper"

class Integrations::Capabilities::DatadogTest < ActiveSupport::TestCase
  RANGE_OBJECT = { "type" => "object", "properties" => { "query" => { "type" => "string" }, "service" => { "type" => "string" },
                                                         "time_range" => { "type" => "object", "properties" => { "from" => {}, "to" => {} } } } }.freeze
  TOP_LEVEL = { "type" => "object", "properties" => { "query" => { "type" => "string" }, "from" => {}, "to" => {}, "limit" => {} } }.freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @northflank_row = northflank.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { token: "x" }.to_json)
    %w[search_logs describe_resource].each do |name|
      northflank.tools.create!(name: name, description: name, read_only: true, enabled: true, params_schema: { "type" => "object" })
    end
    datadog = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "datadog", name: "Datadog", slug: "datadog",
                                              settings: { "server_url" => "https://mcp.datadoghq.com/api/unstable/mcp-server/mcp" })
    @datadog_row = datadog.integration_environments.create!
    @logs = datadog.tools.create!(name: "search_datadog_logs", description: "Logs", read_only: true, enabled: true, params_schema: RANGE_OBJECT)
    datadog.tools.create!(name: "search_datadog_spans", description: "Spans", read_only: true, enabled: true, params_schema: TOP_LEVEL)
    ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "team/prod", kind: ResourceMap::KIND_SERVICE, external_id: "web-id",
                                  name: "web", integration_environment: @northflank_row, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  test "Datadog answers logs for a service Northflank runs by default, and Northflank answers its status" do
    logs = resolve(Integrations::Capabilities::LOGS, "resource" => "web", "text" => "timeout", "minutes" => 30)

    assert_equal [ @datadog_row, "search_datadog_logs" ], [ logs.environment_row, logs.tool.name ]
    assert_equal "\"timeout\"", logs.arguments["query"]
    assert_equal "web", logs.arguments["service"]
    assert_equal({ "from" => "now-30m", "to" => "now" }, logs.arguments["time_range"])
    assert_equal @northflank_row, resolve(Integrations::Capabilities::STATUS, "resource" => "web").environment_row
  end

  test "Datadog is passed over when its tool is off, the caller may not run it, or it cannot take what was asked" do
    @logs.update!(enabled: false)
    assert_equal @northflank_row, resolve(Integrations::Capabilities::LOGS, "resource" => "web").environment_row
    @logs.update!(enabled: true)

    northflank_only = Integration::Tool.in_workspace(@workspace).reject { |tool| tool.integration.provider == "datadog" }
    assert_equal @northflank_row, Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::LOGS, { "resource" => "web" }, northflank_only).environment_row
    assert_equal @northflank_row, resolve(Integrations::Capabilities::LOGS, "resource" => "web", "stream" => "build").environment_row
    assert_equal @northflank_row, resolve(Integrations::Capabilities::LOGS, "resource" => "web", "regex" => "time.?out").environment_row
  end

  test "a Datadog connection wired to another environment does not answer for this one" do
    @datadog_row.update!(catalog_entry_id: catalog_entries(:development_env).id)

    assert_equal @northflank_row, resolve(Integrations::Capabilities::LOGS, "resource" => "web").environment_row
    assert_match "no connection offers traces", unroutable(Integrations::Capabilities::TRACES, "resource" => "web")
  end

  test "when Datadog cannot take what was asked and nothing else can answer, it says why" do
    ResourceMap::Resource.create!(workspace: @workspace, provider: "render", account: "acme", kind: ResourceMap::KIND_SERVICE, external_id: "api-id",
                                  name: "api", first_seen_at: Time.current, last_seen_at: Time.current)

    assert_match "stream must be app", unroutable(Integrations::Capabilities::LOGS, "resource" => "api", "stream" => "build")
    assert_equal @datadog_row, resolve(Integrations::Capabilities::LOGS, "resource" => "api").environment_row
  end

  test "naming a connection asks it instead, and all asks every one, each in its own call" do
    assert_equal @northflank_row, resolve(Integrations::Capabilities::LOGS, "resource" => "web", "connection" => "northflank").environment_row

    calls = Integrations::Capabilities.resolve_all(@workspace, Integrations::Capabilities::LOGS, "resource" => "web", "connection" => "all")
    assert_equal %w[northflank.search_logs datadog.search_datadog_logs].sort, calls.map { |call| call.tool.action_key }.sort

    build = Integrations::Capabilities.resolve_all(@workspace, Integrations::Capabilities::LOGS, "resource" => "web", "connection" => "all", "stream" => "build")
    refused = build.grep(Integrations::Capabilities::Refused).sole
    assert_equal [ @datadog_row, true ], [ refused.environment_row, refused.reason.include?("stream must be app") ]
    assert_equal "northflank.search_logs", build.grep(Integrations::Capabilities::Call).sole.tool.action_key
    assert_raises(Integrations::Capabilities::Unroutable) { Integrations::Capabilities.resolve_all(@workspace, Integrations::Capabilities::ROLLBACK, "resource" => "web", "to" => "x") }
  end

  test "the connection choice offers all for reading only, and points Halon at the team's instructions" do
    connections = %w[northflank datadog]
    logs = Integrations::Capabilities.schema(Integrations::Capabilities.spec(Integrations::Capabilities::LOGS), connections)
    restart = Integrations::Capabilities.schema(Integrations::Capabilities.spec(Integrations::Capabilities::RESTART), connections)

    assert_equal [ *connections, "all" ], logs.dig("properties", "connection", "enum")
    assert_match "team's instructions", logs.dig("properties", "connection", "description")
    assert_equal connections, restart.dig("properties", "connection", "enum")
  end

  test "the arguments follow the parameters the connected server reports, and a service without one goes in the query" do
    spans = resolve(Integrations::Capabilities::TRACES, "resource" => "web", "limit" => 20, "exclude" => "health")

    assert_equal "service:web -\"health\"", spans.arguments["query"]
    assert_equal 20, spans.arguments["limit"]
    assert_equal %w[now-60m now], spans.arguments.values_at("from", "to")
    asked = resolve(Integrations::Capabilities::TRACES, "resource" => "web", "start" => "2026-09-01T10:00:00Z", "end" => "2026-09-01T11:00:00Z")
    assert_equal %w[2026-09-01T10:00:00Z 2026-09-01T11:00:00Z], asked.arguments.values_at("from", "to")
    assert_not spans.arguments.key?("service")
  end

  test "what Datadog cannot do is said, never guessed" do
    assert_match "regular expression", unroutable(Integrations::Capabilities::LOGS, "resource" => "web", "regex" => "x", "connection" => "datadog")
    assert_match "stream must be app", unroutable(Integrations::Capabilities::LOGS, "resource" => "web", "stream" => "build", "connection" => "datadog")
    @logs.update!(params_schema: { "type" => "object", "properties" => { "query" => {} } })
    assert_match "time range in a way Firefight does not know", unroutable(Integrations::Capabilities::LOGS, "resource" => "web", "connection" => "datadog")
    @logs.update!(params_schema: { "type" => "object", "properties" => { "query" => {}, "from" => { "type" => "integer" }, "to" => { "type" => "integer" } } })
    assert_match "time range in a way Firefight does not know", unroutable(Integrations::Capabilities::LOGS, "resource" => "web", "connection" => "datadog")
  end

  private

  def resolve(key, given) = Integrations::Capabilities.resolve(@workspace, key, given)

  def unroutable(key, given) = assert_raises(Integrations::Capabilities::Unroutable) { resolve(key, given) }.message
end
