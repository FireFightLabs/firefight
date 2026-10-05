require "test_helper"

class Integrations::Capabilities::UpstashTest < ActiveSupport::TestCase
  QSTASH = { "type" => "object", "properties" => { "region" => { "type" => "string", "enum" => %w[eu us] },
                                                   "service" => { "type" => "string", "enum" => %w[qstash workflow] }, "count" => { "type" => "integer" } } }.freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    upstash = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "upstash", name: "Upstash", slug: "upstash",
                                              settings: { "server_url" => "https://mcp.upstash.com/mcp" })
    @row = upstash.integration_environments.create!
    database = { "type" => "object", "properties" => { "database_id" => { "type" => "string" } } }
    upstash.tools.create!(name: "redis_get_database", description: "Database", read_only: true, enabled: true, params_schema: database)
    @stats = upstash.tools.create!(name: "redis_get_stats", description: "Stats", read_only: true, enabled: true,
                                   params_schema: database.deep_merge("properties" => { "period" => { "type" => "string", "enum" => %w[1h 3h 12h 1d 3d 7d] } }))
    %w[logs_list dlq_list].each { |name| upstash.tools.create!(name: name, description: name, read_only: true, enabled: true, params_schema: QSTASH) }
    seen = { first_seen_at: Time.current, last_seen_at: Time.current, workspace: @workspace, provider: "upstash", account: "upstash", integration_environment: @row }
    ResourceMap::Resource.create!(kind: ResourceMap::KIND_DATABASE, external_id: "96ad0856", name: "sessions", **seen)
    ResourceMap::Resource.create!(kind: ResourceMap::KIND_QUEUE, external_id: "qstash-eu", name: "QStash eu", details: { "region" => "eu" }, **seen)
  end

  test "a Redis database answers status and metrics by its id, never asking for credentials" do
    status = resolve(Integrations::Capabilities::STATUS, "resource" => "sessions")
    assert_equal [ "redis_get_database", { "database_id" => "96ad0856" } ], [ status.tool.name, status.arguments ]

    assert_equal({ "database_id" => "96ad0856", "period" => "1h" }, resolve(Integrations::Capabilities::METRICS, "resource" => "sessions").arguments)
    assert_equal "1d", resolve(Integrations::Capabilities::METRICS, "resource" => "sessions", "minutes" => 1000).arguments["period"]
    @stats.update!(params_schema: { "type" => "object", "properties" => { "database_id" => {} } })
    assert_not resolve(Integrations::Capabilities::METRICS, "resource" => "sessions").arguments.key?("period")
    assert_match "does not keep cpu", unroutable(Integrations::Capabilities::METRICS, "resource" => "sessions", "metrics" => [ "cpu" ])
  end

  test "Upstash's stats are drawn as charts of the range asked, keeping the link to the console" do
    travel_to Time.utc(2026, 10, 1, 12) do
      call = resolve(Integrations::Capabilities::METRICS, "resource" => "sessions", "metrics" => %w[requests disk], "minutes" => 30)
      stats = { "throughput" => [ { "x" => "2026-10-01 11:40:00.1 +0000 UTC", "y" => 12 }, { "x" => "2026-10-01 10:00:00 +0000 UTC", "y" => 99 } ],
                "diskusage" => [ { "x" => "2026-10-01 11:40:00 +0000 UTC", "y" => 2_097_152 } ] }
      link = Integrations::Telemetry.link_line(Integrations::Telemetry::Link.new(provider: "the Upstash console", url: "https://console.upstash.com/redis"))
      answer = call.present_result({ "content" => [ { "type" => "text", "text" => stats.to_json }, { "type" => "text", "text" => link } ] })
      charts = answer.dig("structuredContent", "charts")

      assert_equal [ "Commands of sessions", "Data size of sessions" ], charts.map { |chart| chart["title"] }
      assert_equal [ 12.0 ], charts.first["series"].first["points"].map(&:last)
      assert_equal [ 2.0 ], charts.second["series"].first["points"].map(&:last)
      assert_equal link, answer["content"].last["text"]
      assert_equal "https://console.upstash.com/redis", charts.first["link"]
    end
  end

  test "the QStash of a region answers its delivery logs, filtered by time and text, and its dead letter queue as errors" do
    travel_to Time.utc(2026, 10, 1, 12) do
      logs = resolve(Integrations::Capabilities::LOGS, "resource" => "QStash eu", "text" => "orders", "limit" => 50)
      assert_equal({ "region" => "eu", "service" => "qstash", "count" => 50 }, logs.arguments)

      now = Time.current.to_i * 1000
      entries = { "logs" => [ { "time" => now - 60_000, "state" => "ERROR", "url" => "https://api.example.com/orders", "responseStatus" => 500, "messageId" => "msg_1" },
                              { "time" => now - 60_000, "state" => "DELIVERED", "url" => "https://api.example.com/mail", "messageId" => "msg_2" },
                              { "time" => now - 7_200_000, "state" => "ERROR", "url" => "https://api.example.com/orders", "messageId" => "msg_0" } ] }
      text = logs.present_result({ "content" => [ { "type" => "text", "text" => entries.to_json } ] })["content"].first["text"]
      assert_match "1 log lines", text
      assert_match "ERROR, https://api.example.com/orders, status 500, message msg_1", text

      dlq = resolve(Integrations::Capabilities::ERRORS, "resource" => "QStash eu")
      messages = { "messages" => [ { "messageId" => "a", "url" => "https://api.example.com/orders", "responseStatus" => 502, "createdAt" => now - 1000 },
                                   { "messageId" => "b", "url" => "https://api.example.com/orders", "responseStatus" => 502, "createdAt" => now - 2000 } ] }
      grouped = dlq.present_result({ "content" => [ { "type" => "text", "text" => messages.to_json } ] })["content"].first["text"]
      assert_match "https://api.example.com/orders, last answered 502: 2 messages", grouped
    end
    assert_match "regular expression", unroutable(Integrations::Capabilities::LOGS, "resource" => "QStash eu", "regex" => "x")
    assert_match "stream must be app or requests", unroutable(Integrations::Capabilities::LOGS, "resource" => "QStash eu", "stream" => "build")
  end

  test "a tool whose parameters Firefight does not know is refused in words, and Upstash's own tools stay offered" do
    @workspace.integrations.find_by!(slug: "upstash").tools.find_by!(name: "logs_list").update!(params_schema: { "type" => "object", "properties" => {} })

    assert_match "takes its region in a way Firefight does not know", unroutable(Integrations::Capabilities::LOGS, "resource" => "QStash eu")
    assert_empty Integrations::Capabilities::Upstash::WRAPPED
  end

  private

  def resolve(key, given) = Integrations::Capabilities.resolve(@workspace, key, given, principal: map_reader)

  def unroutable(key, given) = assert_raises(Integrations::Capabilities::Unroutable) { resolve(key, given) }.message
end
