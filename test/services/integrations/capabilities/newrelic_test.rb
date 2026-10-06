require "test_helper"

class Integrations::Capabilities::NewrelicTest < ActiveSupport::TestCase
  NRQL_SCHEMA = { "type" => "object", "properties" => { "account_id" => { "type" => "integer" }, "query" => { "type" => "string" } },
                  "required" => %w[account_id query] }.freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @northflank_row = northflank.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { token: "x" }.to_json)
    %w[search_logs query_metrics list_deployments describe_resource].each do |name|
      northflank.tools.create!(name: name, description: name, read_only: true, enabled: true, params_schema: { "type" => "object" })
    end
    newrelic = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "newrelic", name: "New Relic", slug: "newrelic",
                                               settings: { "server_url" => "https://mcp.newrelic.com/mcp/", "region" => "us" })
    @newrelic_row = newrelic.integration_environments.create!
    @newrelic_row.store_fields!("account_id" => "1234567")
    @nrql = newrelic.tools.create!(name: "execute_nrql_query", description: "NRQL", read_only: true, enabled: true, params_schema: NRQL_SCHEMA)
    ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "team/prod", kind: ResourceMap::KIND_SERVICE, external_id: "web-id",
                                  name: "web", integration_environment: @northflank_row, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  test "New Relic answers logs, errors and traces for a service Northflank runs by default, in the account its environment reads" do
    logs = resolve(Integrations::Capabilities::LOGS, "resource" => "web", "text" => "timeout", "exclude" => "health", "minutes" => 30)

    assert_equal [ @newrelic_row, "execute_nrql_query" ], [ logs.environment_row, logs.tool.name ]
    assert_equal 1_234_567, logs.arguments["account_id"]
    assert_equal "SELECT timestamp, level, log.level, message, hostname, trace.id, entity.guid FROM Log " \
                 "WHERE (entity.name = 'web' OR service.name = 'web') AND message LIKE '%timeout%' AND message NOT LIKE '%health%' " \
                 "SINCE 30 minutes ago ORDER BY timestamp DESC LIMIT 100", logs.arguments["query"]

    errors = resolve(Integrations::Capabilities::ERRORS, "resource" => "web", "limit" => 5)
    assert_match "FROM TransactionError WHERE appName = 'web' FACET error.class, error.message SINCE 60 minutes ago LIMIT 5", errors.arguments["query"]
    traces = resolve(Integrations::Capabilities::TRACES, "resource" => "web", "start" => "2026-09-01T10:00:00Z", "end" => "2026-09-01T11:00:00Z")
    assert_match "FROM Transaction WHERE appName = 'web' SINCE '2026-09-01T10:00:00Z' UNTIL '2026-09-01T11:00:00Z' ORDER BY duration DESC LIMIT 20",
                 traces.arguments["query"]
    assert_equal [ @northflank_row, "search_logs" ], [ logs.fallback.environment_row, logs.fallback.tool.name ]
  end

  test "a site's errors are its pages' JavaScript errors, and New Relic answers only errors for a site" do
    ResourceMap::Resource.create!(workspace: @workspace, provider: "netlify", account: "acme", kind: ResourceMap::KIND_SITE, external_id: "shop-id",
                                  name: "shop", first_seen_at: Time.current, last_seen_at: Time.current)

    errors = resolve(Integrations::Capabilities::ERRORS, "resource" => "shop", "text" => "undefined")
    assert_equal @newrelic_row, errors.environment_row
    assert_match "FROM JavaScriptError WHERE appName = 'shop' AND errorMessage LIKE '%undefined%' FACET errorClass, errorMessage", errors.arguments["query"]
    assert_match "no connection offers logs", unroutable(Integrations::Capabilities::LOGS, "resource" => "shop")
  end

  test "the platform answers status and deploys, and New Relic answers deploys for a service nothing else holds" do
    assert_equal @northflank_row, resolve(Integrations::Capabilities::STATUS, "resource" => "web").environment_row
    assert_equal @northflank_row, resolve(Integrations::Capabilities::DEPLOYS, "resource" => "web").environment_row
    render_service

    deploys = resolve(Integrations::Capabilities::DEPLOYS, "resource" => "api")
    assert_equal @newrelic_row, deploys.environment_row
    assert_match "FROM Deployment, ChangeTrackingEvent WHERE entity.name = 'api' SINCE 30 days ago ORDER BY timestamp DESC LIMIT 20", deploys.arguments["query"]
  end

  test "New Relic answers requests and errors per minute, and the platform every other metric" do
    metrics = resolve(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => %w[requests errors], "minutes" => 600)

    assert_equal @newrelic_row, metrics.environment_row
    assert_equal "SELECT count(*) AS 'transactions', filter(count(*), WHERE transactionType = 'Web') / 5 AS 'requests', " \
                 "filter(count(*), WHERE error IS TRUE) / 5 AS 'errors' FROM Transaction WHERE appName = 'web' SINCE 600 minutes ago TIMESERIES 5 minutes",
                 metrics.arguments["query"]
    assert_equal @northflank_row, resolve(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => %w[requests cpu]).environment_row
    assert_equal @northflank_row, resolve(Integrations::Capabilities::METRICS, "resource" => "web").environment_row
    assert_match "does not keep cpu", unroutable(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => [ "cpu" ], "connection" => "newrelic")
  end

  test "requests compare with the throughput New Relic's baselines keep, and errors, kept there as a share, with nothing" do
    assert_equal "throughput", Integrations::Capabilities.baseline_metric(@newrelic_row, "requests", ResourceMap::KIND_SERVICE)
    assert_nil Integrations::Capabilities.baseline_metric(@newrelic_row, "errors", ResourceMap::KIND_SERVICE)
    assert Integrations::BaselineReaders::Newrelic::METRICS.key?("throughput")
  end

  test "a metrics answer becomes a chart per metric, and one with no transactions says so and lets the platform answer" do
    travel_to Time.utc(2026, 9, 1, 12) do
      metrics = resolve(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => [ "requests" ], "minutes" => 2)
      link = Integrations::Telemetry.link_line(Integrations::Telemetry::Link.new(provider: "New Relic", url: "https://one.newrelic.com/redirect/entity/abc"))
      rows = [ { "beginTimeSeconds" => 1_788_264_000 - 120, "endTimeSeconds" => 1_788_264_000 - 60, "transactions" => 30, "requests" => 24.0 },
               { "beginTimeSeconds" => 1_788_264_000 - 60, "endTimeSeconds" => 1_788_264_000, "transactions" => 40, "requests" => 36.0 } ]

      presented = metrics.present_result(answer({ "results" => rows }, link))
      chart = presented.dig("structuredContent", "charts").sole
      assert_equal [ "Requests of web", "per minute" ], chart.values_at("title", "unit")
      assert_equal [ 24.0, 36.0 ], chart["series"].sole["points"].map(&:last)
      assert_equal link, presented["content"].last["text"]
      assert Integrations::Capabilities.definitive?(presented)

      none = metrics.present_result(answer({ "results" => rows.map { |row| row.merge("transactions" => 0, "requests" => 0) } }))
      assert_match "no transactions for web", none["content"].first["text"]
      assert_not Integrations::Capabilities.definitive?(none)

      unknown = answer("Query ran")
      assert_equal unknown, metrics.present_result(unknown)
    end
  end

  test "New Relic is passed over without an account, a switched off tool, or a stream it does not keep, and says so when named" do
    @newrelic_row.store_fields!({})
    assert_equal @northflank_row, resolve(Integrations::Capabilities::LOGS, "resource" => "web").environment_row
    assert_match "give its account id", unroutable(Integrations::Capabilities::LOGS, "resource" => "web", "connection" => "newrelic")
    @newrelic_row.store_fields!("account_id" => "1234567")

    assert_equal @northflank_row, resolve(Integrations::Capabilities::LOGS, "resource" => "web", "stream" => "build").environment_row
    assert_match "stream must be app", unroutable(Integrations::Capabilities::LOGS, "resource" => "web", "stream" => "build", "connection" => "newrelic")
    @nrql.update!(enabled: false)
    assert_match "no connection offers errors", unroutable(Integrations::Capabilities::ERRORS, "resource" => "web")
  end

  test "a regular expression goes to RLIKE matched anywhere in a line, and text NRQL cannot quote is refused" do
    logs = resolve(Integrations::Capabilities::LOGS, "resource" => "web", "regex" => "time.?out", "connection" => "newrelic")
    assert_match "message RLIKE r'(?s).*(?:time.?out).*'", logs.arguments["query"]

    assert_match "quote or a backslash", unroutable(Integrations::Capabilities::LOGS, "resource" => "web", "text" => "it's", "connection" => "newrelic")
    assert_match "regular expression with a quote", unroutable(Integrations::Capabilities::LOGS, "resource" => "web", "regex" => "a'b", "connection" => "newrelic")
  end

  test "the arguments follow the parameters the connected server reports, and one it does not have is never sent" do
    @nrql.update!(params_schema: { "type" => "object", "properties" => { "nrql_query" => {}, "accountId" => { "type" => "string" } } })
    logs = resolve(Integrations::Capabilities::LOGS, "resource" => "web", "connection" => "newrelic")
    assert_equal %w[accountId nrql_query], logs.arguments.keys.sort
    assert_equal "1234567", logs.arguments["accountId"]

    @nrql.update!(params_schema: { "type" => "object", "properties" => { "query" => {} } })
    assert_equal [ "query" ], resolve(Integrations::Capabilities::LOGS, "resource" => "web", "connection" => "newrelic").arguments.keys

    @nrql.update!(params_schema: { "type" => "object", "properties" => { "statement" => {} } })
    assert_match "takes its query in a way Firefight does not know", unroutable(Integrations::Capabilities::LOGS, "resource" => "web", "connection" => "newrelic")
  end

  test "a New Relic connection wired to another environment does not answer for this one" do
    @newrelic_row.update!(catalog_entry_id: catalog_entries(:development_env).id)

    assert_equal @northflank_row, resolve(Integrations::Capabilities::LOGS, "resource" => "web").environment_row
    assert_match "no connection offers traces", unroutable(Integrations::Capabilities::TRACES, "resource" => "web")
  end

  test "Halon is told what it can ask New Relic, and its query tool stays offered" do
    assert_equal "Halon can read its logs, read its metrics, see what was deployed, read its errors, and read its traces for the services on " \
                 "the map that New Relic watches, by their name in New Relic, through the tools you switch on. It also uses New Relic's other " \
                 "tools that you switch on.", Integrations::Capabilities.halon_sentence("newrelic", "New Relic")
    assert_not Integrations::Capabilities.wrapped?(@nrql)
  end

  test "the account the adapter reads is the one the connect form asks for, and each region has its server and site" do
    entry = IntegrationProvider.find("newrelic")

    assert_equal [ Integrations::Capabilities::Newrelic::ACCOUNT_SETTING ], entry.connect_fields.map(&:key)
    assert entry.connect_fields.sole.numeric
    assert_equal [ %w[us https://mcp.newrelic.com/mcp/ https://one.newrelic.com], %w[eu https://mcp.eu.newrelic.com/mcp/ https://one.eu.newrelic.com],
                   %w[jp https://mcp.jp.newrelic.com/mcp/ https://one.jp.newrelic.com] ], entry.regions.map { |region| [ region.key, region.server_url, region.site ] }
  end

  private

  def render_service
    ResourceMap::Resource.create!(workspace: @workspace, provider: "render", account: "acme", kind: ResourceMap::KIND_SERVICE, external_id: "api-id",
                                  name: "api", first_seen_at: Time.current, last_seen_at: Time.current)
  end

  def answer(body, *lines)
    text = body.is_a?(String) ? body : body.to_json
    { "content" => [ { "type" => "text", "text" => text }, *lines.map { |line| { "type" => "text", "text" => line } } ] }
  end

  def resolve(key, given) = Integrations::Capabilities.resolve(@workspace, key, given, principal: map_reader)

  def unroutable(key, given) = assert_raises(Integrations::Capabilities::Unroutable) { resolve(key, given) }.message
end
