require "test_helper"

class Integrations::Capabilities::CloudflareTest < ActiveSupport::TestCase
  ACCOUNT = "acc123".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @integration = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "cloudflare", name: "Cloudflare", slug: "cloudflare",
                                                   settings: { "server_url" => "https://mcp.cloudflare.com/mcp" })
    @row = @integration.integration_environments.create!
    @integration.tools.create!(name: "execute", description: "Runs a script", read_only: false, enabled: true, params_schema: { "type" => "object" })
    @worker = resource!(ResourceMap::KIND_WORKER, "api-worker", "api-worker", "workers-and-pages")
    @zone = resource!(ResourceMap::KIND_ZONE, "zone-1", "example.com", "example.com")
    @site = resource!(ResourceMap::KIND_SITE, "docs", "docs", "workers-and-pages")
  end

  test "a Worker's logs are one Workers Observability query Firefight writes, and its events read back as log lines" do
    call = resolve(Integrations::Capabilities::LOGS, "resource" => "api-worker", "text" => "timeout", "minutes" => 15)

    options = request_of(call)
    assert_equal [ "POST", "/accounts/#{ACCOUNT}/workers/observability/telemetry/query" ], options.values_at("method", "path")
    assert_equal [ "events", 200, true ], options["body"].values_at("view", "limit", "dry")
    assert_includes call.arguments["code"], "const to = Date.now(); const from = Math.max(to - 15 * 60000"
    assert_includes call.arguments["code"], "request.body.timeframe = { from, to };"
    assert_includes options.dig("body", "parameters", "filters"), { "key" => "$metadata.service", "operation" => "eq", "type" => "string", "value" => "api-worker" }
    assert_equal ACCOUNT, call.arguments["account_id"]

    answer = call.present_result(text_result({ "result" => { "events" => { "events" => [
      { "$metadata" => { "timestamp" => 1_759_400_000_000, "message" => "upstream timeout" } }
    ] } } }))
    assert_match "upstream timeout", answer.dig("content", 0, "text")
    assert_match "https://dash.cloudflare.com/#{ACCOUNT}/workers-and-pages", answer.dig("content", 0, "text")
    assert_raises(Integrations::Capabilities::Unroutable) { resolve(Integrations::Capabilities::LOGS, "resource" => "api-worker", "stream" => "build") }
  end

  test "a Worker's metrics are bucketed into a chart, and a zone's come from its hourly request counts" do
    call = resolve(Integrations::Capabilities::METRICS, "resource" => "api-worker", "metrics" => %w[requests errors], "minutes" => 60)
    assert_equal "/graphql", request_of(call)["path"]
    rows = [ 0, 30, 70 ].map do |seconds|
      { "sum" => { "requests" => 10, "errors" => 1 }, "quantiles" => { "cpuTimeP50" => 2000 }, "dimensions" => { "datetime" => (Time.utc(2026, 10, 3, 10) + seconds).iso8601 } }
    end
    answer = call.present_result(text_result({ "data" => { "viewer" => { "accounts" => [ { "workersInvocationsAdaptive" => rows } ] } } }))
    charts = answer.dig(Integrations::Telemetry::STRUCTURED, Integrations::Telemetry::CHARTS)
    assert_equal [ "Requests of api-worker", "Errors of api-worker" ], charts.map { |chart| chart["title"] }
    assert_equal [ 20.0, 10.0 ], charts.first.dig("series", 0, "points").map(&:last)

    zone = resolve(Integrations::Capabilities::METRICS, "resource" => "example.com", "metrics" => [ "http_5xx" ])
    assert_includes request_of(zone).dig("body", "query"), "edgeResponseStatus_geq: 500"
    answer = zone.present_result(text_result({ "data" => { "viewer" => { "zones" => [ { "server" => [ { "count" => 4, "dimensions" => { "datetimeHour" => "2026-10-03T10:00:00Z" } } ] } ] } } }))
    assert_match "Counted every hour", answer.dig("content", 0, "text")
    assert_match "Cloudflare does not keep cpu",
                 assert_raises(Integrations::Capabilities::Unroutable) { resolve(Integrations::Capabilities::METRICS, "resource" => "example.com", "metrics" => [ "cpu" ]) }.message
  end

  test "deploys list with the id rollback takes, and a rollback is the request Cloudflare's docs give" do
    deploys = resolve(Integrations::Capabilities::DEPLOYS, "resource" => "api-worker")
    assert_equal({ "method" => "GET", "path" => "/accounts/#{ACCOUNT}/workers/scripts/api-worker/deployments" }, request_of(deploys))
    answer = deploys.present_result(text_result({ "result" => { "deployments" => [
      { "id" => "dep-1", "created_on" => "2026-10-03T09:00:00Z", "source" => "wrangler", "author_email" => "a@example.com",
        "versions" => [ { "version_id" => "ver-9", "percentage" => 100 } ] }
    ] } }))
    assert_match "version ver-9 at 100%", answer.dig("content", 0, "text")
    assert_match "rollback takes a version id", answer.dig("content", 0, "text")

    worker = resolve(Integrations::Capabilities::ROLLBACK, "resource" => "api-worker", "to" => "ver-8")
    assert_equal [ { "version_id" => "ver-8", "percentage" => 100 } ], request_of(worker).dig("body", "versions")
    site = resolve(Integrations::Capabilities::ROLLBACK, "resource" => "docs", "to" => "dep-3")
    assert_equal "/accounts/#{ACCOUNT}/pages/projects/docs/deployments/dep-3/rollback", request_of(site)["path"]
  end

  test "the same request reads the same each time, so a replay matches it, and a failed answer is thrown as an error" do
    first = resolve(Integrations::Capabilities::METRICS, "resource" => "api-worker", "minutes" => 30)
    travel 5.minutes
    again = resolve(Integrations::Capabilities::METRICS, "resource" => "api-worker", "minutes" => 30)

    assert_equal first.arguments, again.arguments
    assert_includes first.arguments["code"], "answer.success === false"
    assert_includes first.arguments["code"], "request.body.variables.start = new Date(from).toISOString();"
  end

  test "an error or an answer that is not JSON reaches the agent in Cloudflare's own words" do
    call = resolve(Integrations::Capabilities::STATUS, "resource" => "example.com")
    error = { "content" => [ { "type" => "text", "text" => "Authentication error" } ], "isError" => true }

    assert_equal error, call.present_result(error)
    assert_equal "not json", call.present_result(text_result("not json")).dig("content", 0, "text")
  end

  private

  def resolve(key, given) = Integrations::Capabilities.resolve(@workspace, key, given)

  # The request inside the script Firefight wrote, read back out of its JSON literal.
  def request_of(call)
    JSON.parse(call.arguments["code"][/const request = (\{.*?\}); (?:const to|const answer)/, 1])
  end

  def text_result(data) = { "content" => [ { "type" => "text", "text" => data.is_a?(String) ? data : data.to_json } ] }

  def resource!(kind, id, name, page)
    ResourceMap::Resource.create!(workspace: @workspace, provider: "cloudflare", account: "Acme", kind: kind, external_id: id, name: name,
                                  url: "https://dash.cloudflare.com/#{ACCOUNT}/#{page}", integration_environment: @row,
                                  first_seen_at: Time.current, last_seen_at: Time.current)
  end
end
