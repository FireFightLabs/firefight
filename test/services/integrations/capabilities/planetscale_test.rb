require "test_helper"

class Integrations::Capabilities::PlanetscaleTest < ActiveSupport::TestCase
  Capabilities = Integrations::Capabilities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    planetscale = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "planetscale", name: "PlanetScale", slug: "planetscale",
                                                  settings: { "server_url" => "https://mcp.pscale.dev/mcp/planetscale" })
    @row = planetscale.integration_environments.create!
    Capabilities::Planetscale::TOOLS.each_value do |name|
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

  def resolve(key, given) = Capabilities.resolve(@workspace, key, given)

  def unroutable(key, given) = assert_raises(Capabilities::Unroutable) { resolve(key, given) }.message

  def unroutable_after(change, key, given)
    change.call
    unroutable(key, given)
  end
end
