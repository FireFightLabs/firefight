require "test_helper"

class Integrations::Capabilities::PlanetscaleTest < ActiveSupport::TestCase
  Capabilities = Integrations::Capabilities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    planetscale = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "planetscale", name: "PlanetScale", slug: "planetscale",
                                                  settings: { "server_url" => "https://mcp.pscale.dev/mcp/planetscale" })
    @row = planetscale.integration_environments.create!
    Capabilities::Planetscale::TOOLS.values.flatten.uniq.each do |name|
      planetscale.tools.create!(name: name, description: name, read_only: true, enabled: true, params_schema: { "type" => "object" })
    end
    record(engine: "postgresql")
  end

  test "status reads a branch, and a database through its production branch" do
    branch = resolve(Capabilities::STATUS, "resource" => "shop/main")
    database = resolve(Capabilities::STATUS, "resource" => "shop")

    expected = { "pathParameters" => { "organization" => "acme", "database" => "shop", "branch" => "main" } }
    assert_equal [ "planetscale_get_branch", expected ], [ branch.tool.name, branch.arguments ]
    assert_equal expected, database.arguments
  end

  test "logs filter with LogsQL, each value quoted, over a relative period or a range" do
    call = resolve(Capabilities::LOGS, "resource" => "shop", "text" => "say \"hi\"", "exclude" => "checkpoint", "regex" => "dead.?lock", "minutes" => 15)

    assert_equal({ "organization" => "acme", "database" => "shop", "branch" => "main", "limit" => 200, "period" => "15m",
                   "query" => "\"say \\\"hi\\\"\" -\"checkpoint\" ~\"dead.?lock\"" }, call.arguments)
    ranged = resolve(Capabilities::LOGS, "resource" => "shop/main", "start" => "2026-10-01T10:00:00Z", "end" => "2026-10-01T11:00:00Z")
    assert_equal %w[2026-10-01T10:00:00Z 2026-10-01T11:00:00Z], ranged.arguments.values_at("from", "to")
  end

  test "the server's log entries read newest first, by the pod that wrote them" do
    call = resolve(Capabilities::LOGS, "resource" => "shop/main")
    body = { "branch" => "main", "logs" => [ { "time" => "2026-10-04T09:00:00Z", "level" => "INFO", "message" => "checkpoint complete", "pod" => "pg-0", "role" => "primary" },
                                             { "time" => "2026-10-04T09:05:00Z", "level" => "ERROR", "message" => "deadlock detected", "pod" => "pg-1", "role" => "replica" } ] }
    text = call.present_result({ "content" => [ { "type" => "text", "text" => body.to_json } ] })["content"].first["text"]

    assert_match(/2026-10-04T09:05:00Z pg-1 \(replica\) ERROR deadlock detected\n2026-10-04T09:00:00Z pg-0 \(primary\) INFO checkpoint complete/, text)
    said = { "content" => [ { "type" => "text", "text" => "Error: Logs not available. (status: 404)" } ] }
    assert_equal said, call.present_result(said)
  end

  test "a MySQL database, or a stream other than the server's, is refused with why" do
    assert_match "stream must be app", unroutable(Capabilities::LOGS, "resource" => "shop", "stream" => "requests")
    assert_match "only for Postgres", unroutable_after(-> { record(engine: "mysql") }, Capabilities::LOGS, "resource" => "shop/main")
  end

  test "a database the map knows no production branch of asks for the branch" do
    ResourceMap.record!(@row, ResourceMap::Snapshot.new(resources: [ found(ResourceMap::KIND_DATABASE, "shop") ]))

    assert_match "name its branch, such as shop/main", unroutable(Capabilities::STATUS, "resource" => "shop")
  end

  test "run history is a database's deploy requests, a branch's into it, one by its number, or a branch's changes" do
    database = resolve(Capabilities::HISTORY, "resource" => "shop")
    assert_equal [ "planetscale_list_deploy_requests", { "organization" => "acme", "database" => "shop" } ], [ database.tool.name, database.arguments ]
    branch = resolve(Capabilities::HISTORY, "resource" => "shop/main", "limit" => 5)
    assert_equal({ "organization" => "acme", "database" => "shop", "into_branch" => "main", "limit" => 5 }, branch.arguments)
    one = resolve(Capabilities::HISTORY, "resource" => "shop/main", "run" => "#7")
    assert_equal [ "planetscale_get_deploy_request", { "organization" => "acme", "database" => "shop", "number" => "7" } ], [ one.tool.name, one.arguments ]
    changes = resolve(Capabilities::HISTORY, "resource" => "shop", "name" => "resize")
    assert_equal [ "planetscale_list_branch_changes", { "organization" => "acme", "database" => "shop", "branch" => "main" } ], [ changes.tool.name, changes.arguments ]

    run = Capabilities::History::Run.new(id: "7", number: 7, name: "deploy request", status: Capabilities::History::SUCCEEDED,
                                         started_at: Time.zone.parse("2026-10-20T09:00:00Z"), finished_at: Time.zone.parse("2026-10-20T09:06:00Z"))
    answered = Capabilities::RunHistory.with_runs(Integrations::Telemetry.result("Latest", link: nil), [ run ])
    assert_match "1 recent runs of the deploy requests of shop, newest first. Finished ones usually take 6 minutes", database.present_result(answered)["content"].sole["text"]
  end

  test "deploys are the deploy requests deployed, and a rollback reverts one by its number" do
    assert_equal({ "organization" => "acme", "database" => "shop", "into_branch" => "main", "state" => "deployed" },
                 resolve(Capabilities::DEPLOYS, "resource" => "shop/main").arguments)
    rollback = resolve(Capabilities::ROLLBACK, "resource" => "shop/main", "to" => "#7")
    assert_equal [ "planetscale_revert_deploy_request", { "organization" => "acme", "database" => "shop", "number" => 7 } ], [ rollback.tool.name, rollback.arguments ]
    assert_match "say its number", unroutable(Capabilities::ROLLBACK, "resource" => "shop", "to" => "main")
  end

  test "a Postgres branch scales by its cluster size and replicas, and a Vitess one is sent to the tool that names a keyspace" do
    call = resolve(Capabilities::SCALE, "resource" => "shop", "plan" => "PS_80", "instances" => 3)
    assert_equal [ "planetscale_resize_branch", { "organization" => "acme", "database" => "shop", "branch" => "main", "cluster_size" => "PS_80", "replicas" => 3 } ],
                 [ call.tool.name, call.arguments ]
    assert_match "naming the keyspace", unroutable_after(-> { record(engine: "mysql") }, Capabilities::SCALE, "resource" => "shop", "plan" => "PS_80")
  end

  test "metrics read the branch's own series by the engine's names, one chart a metric and a series a pod" do
    call = resolve(Capabilities::METRICS, "resource" => "shop", "metrics" => %w[cpu disk], "minutes" => 90)
    assert_equal({ "organization" => "acme", "database" => "shop", "branch" => "main", "view" => "series", "include_points" => true, "period" => "3h",
                   "metrics" => %w[planetscale_primary_pods_cpu_util_percentages planetscale_volume_usage_percentages] }, call.arguments)
    body = { "series" => [ { "metric" => "planetscale_primary_pods_cpu_util_percentages", "labels" => { "pod" => "pg-0" }, "points" => [ [ 1_760_950_800, 41.5 ], [ 1_760_950_860, 63.0 ] ] } ] }
    result = call.present_result({ "content" => [ { "type" => "text", "text" => body.to_json } ] })
    chart = result.dig(Integrations::Telemetry::STRUCTURED, Integrations::Telemetry::CHARTS).sole
    assert_equal [ "cpu of shop", "%", "pg-0" ], [ chart["title"], chart["unit"], chart["series"].sole["label"] ]
    assert_match "does not keep network_in", unroutable(Capabilities::METRICS, "resource" => "shop", "metrics" => [ "network_in" ])
  end

  test "errors are the branch's failing queries by error, over at most a day" do
    call = resolve(Capabilities::ERRORS, "resource" => "shop/main", "text" => "deadlock", "minutes" => 60)
    assert_equal({ "organization" => "acme", "database" => "shop", "branch" => "main", "limit" => 25, "period" => "1h", "query" => "deadlock" }, call.arguments)
    body = { "patterns" => [ { "error_fingerprint" => "f1", "error_message" => "Deadlock found", "error_count" => 12, "started_at" => "2026-10-20T09:00:00Z" } ] }
    text = call.present_result({ "content" => [ { "type" => "text", "text" => body.to_json } ] })["content"].first["text"]
    assert_match "12 times, last 2026-10-20T09:00:00Z: Deadlock found (fingerprint f1)", text
    assert_match "at most 25 hours", unroutable(Capabilities::ERRORS, "resource" => "shop", "minutes" => 2000)
  end

  test "PlanetScale's own tools stay offered" do
    assert_not Capabilities::Planetscale.wraps?("planetscale_get_branch")
  end

  private

  def found(kind, id, details = {}) = ResourceMap::Found.new(provider: "planetscale", account: "acme", kind: kind, external_id: id, name: id, details: details)

  def record(engine:)
    database = found(ResourceMap::KIND_DATABASE, "shop", { "engine" => engine })
    branch = found(ResourceMap::KIND_BRANCH, "shop/main", { ResourceMap::PRODUCTION => true })
    ResourceMap.record!(@row, ResourceMap::Snapshot.new(resources: [ database, branch ],
                                                        links: [ ResourceMap::FoundLink.new(from: branch.key, to: database.key, relation: ResourceMap::RELATION_BRANCH_OF) ]))
  end

  def resolve(key, given) = Capabilities.resolve(@workspace, key, given, principal: map_reader)

  def unroutable(key, given) = assert_raises(Capabilities::Unroutable) { resolve(key, given) }.message

  def unroutable_after(change, key, given)
    change.call
    unroutable(key, given)
  end
end
