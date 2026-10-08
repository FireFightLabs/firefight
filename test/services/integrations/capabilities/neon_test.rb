require "test_helper"

class Integrations::Capabilities::NeonTest < ActiveSupport::TestCase
  Capabilities = Integrations::Capabilities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    neon = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "neon", name: "Neon", slug: "neon", settings: { "server_url" => "https://mcp.neon.tech/mcp" })
    @row = neon.integration_environments.create!
    Capabilities::Neon::TOOLS.values.uniq.each do |name|
      neon.tools.create!(name: name, description: name, read_only: name != "restart_postgres_endpoint", enabled: true, params_schema: { "type" => "object" })
    end
    found = ->(kind, id, name) { ResourceMap::Found.new(provider: "neon", account: "Acme", kind: kind, external_id: id, name: name, url: "https://console.neon.tech/app/projects/shop-123") }
    @project = found.(ResourceMap::KIND_DATABASE, "shop-123", "shop")
    @branch = found.(ResourceMap::KIND_BRANCH, "shop-123/br-main-1", "shop/main")
    @compute = found.(ResourceMap::KIND_COMPUTE, "shop-123/ep-cool-1", "ep-cool-1")
    ResourceMap.record!(@row, ResourceMap::Snapshot.new(resources: [ @project, @branch, @compute ]))
  end

  test "status reads the computes that serve a project, a branch or one compute, each by its branch's name" do
    call = resolve(Capabilities::STATUS, "resource" => "shop/main")
    assert_equal [ "list_postgres_endpoints", { "project_id" => "shop-123" } ], [ call.tool.name, call.arguments ]

    endpoints = [ { "id" => "ep-cool-1", "branch_id" => "br-main-1", "type" => "read_write", "current_state" => "active", "autoscaling_limit_min_cu" => 0.25,
                    "autoscaling_limit_max_cu" => 2, "suspend_timeout_seconds" => 0, "last_active" => "2026-10-04T09:00:00Z" },
                  { "id" => "ep-other-2", "branch_id" => "br-preview-2", "type" => "read_write", "current_state" => "idle", "suspend_timeout_seconds" => -1 } ]
    text = answer_text(call, endpoints)
    assert_match "How shop/main stands on Neon now, by the computes that serve it:", text
    assert_match "compute ep-cool-1 (read write), on branch shop/main, active, 0.25 to 2 CU, suspends when idle after the default time", text
    assert_no_match "ep-other-2", text
    assert_match "never suspends", answer_text(resolve(Capabilities::STATUS, "resource" => "shop"), endpoints)
    assert_match "No compute serves ep-cool-1", answer_text(resolve(Capabilities::STATUS, "resource" => "ep-cool-1"), [])
  end

  test "logs read a branch by its ids, with text, a relative window or a range, and newest first" do
    call = resolve(Capabilities::LOGS, "resource" => "shop/main", "text" => "timeout", "minutes" => 30, "limit" => 50)
    assert_equal({ "project_id" => "shop-123", "branch_id" => "br-main-1", "limit" => 50, "sort_order" => "desc", "body_contains" => "timeout", "since" => "30m" },
                 call.arguments)
    ranged = resolve(Capabilities::LOGS, "resource" => "shop/main", "start" => "2026-10-01T10:00:00Z", "end" => "2026-10-01T11:00:00Z")
    assert_equal %w[2026-10-01T10:00:00Z 2026-10-01T11:00:00Z], ranged.arguments.values_at("start_time", "end_time")

    records = [ { "timestamp" => "2026-10-04T09:00:00Z", "message" => "older", "service_name" => "api" },
                { "timestamp" => "2026-10-04T09:01:00Z", "message" => "request timed out", "severity_text" => "ERROR", "source" => "function" } ]
    text = answer_text(call, records)
    assert_match "2 log lines for branch shop/main, newest first.", text
    assert_match(/2026-10-04T09:01:00Z function ERROR request timed out\n2026-10-04T09:00:00Z api older/, text)
    assert_match "Postgres does not write to them yet", answer_text(call, [])
  end

  test "what Neon's log search cannot do is said, and a project or a compute has no logs of its own" do
    assert_match "not a regular expression", unroutable(Capabilities::LOGS, "resource" => "shop/main", "regex" => "time.?out")
    assert_match "cannot leave lines out", unroutable(Capabilities::LOGS, "resource" => "shop/main", "exclude" => "health")
    assert_match "stream must be app", unroutable(Capabilities::LOGS, "resource" => "shop/main", "stream" => "build")
    assert_match "no connection offers logs", unroutable(Capabilities::LOGS, "resource" => "shop")
  end

  test "deploys are the operations Neon ran on the resource, newest first" do
    call = resolve(Capabilities::DEPLOYS, "resource" => "ep-cool-1")
    assert_equal({ "project_id" => "shop-123", "limit" => Capabilities::Neon::OPERATIONS_READ }, call.arguments)

    operations = [ { "id" => "1", "endpoint_id" => "ep-cool-1", "branch_id" => "br-main-1", "action" => "start_compute", "status" => "finished",
                     "created_at" => "2026-10-04T08:00:00Z", "total_duration_ms" => 1500 },
                   { "id" => "2", "endpoint_id" => "ep-cool-1", "action" => "apply_config", "status" => "failed", "error" => "timeout",
                     "created_at" => "2026-10-04T09:00:00Z" },
                   { "id" => "3", "endpoint_id" => "ep-other-2", "action" => "suspend_compute", "status" => "finished", "created_at" => "2026-10-04T09:30:00Z" } ]
    text = answer_text(call, operations)
    assert_match "Latest 2 operations Neon ran on ep-cool-1", text
    assert_match(/2026-10-04T09:00:00Z, apply config, failed, failed \(timeout\)\n2026-10-04T08:00:00Z, start compute, finished, on branch br-main-1, took 1.5s/, text)
    assert_match "Neon ran no operations on shop/main", answer_text(resolve(Capabilities::DEPLOYS, "resource" => "shop/main"), [])
  end

  test "a restart names one compute and is a change the person confirms" do
    call = resolve(Capabilities::RESTART, "resource" => "ep-cool-1")

    assert_equal [ "restart_postgres_endpoint", { "project_id" => "shop-123", "endpoint_id" => "ep-cool-1" } ], [ call.tool.name, call.arguments ]
    assert call.spec.writes
    assert_match "Neon is restarting ep-cool-1", answer_text(call, { "id" => "ep-cool-1", "current_state" => "active" })
    assert_match "no connection offers a restart", unroutable(Capabilities::RESTART, "resource" => "shop/main")
  end

  test "an error from Neon reaches the agent as Neon said it" do
    failed = { "isError" => true, "content" => [ { "type" => "text", "text" => "telemetry_not_enabled" } ] }

    assert_equal failed, resolve(Capabilities::LOGS, "resource" => "shop/main").present_result(failed)
  end

  test "Halon says what it can do through Neon" do
    assert_equal "Halon can read its logs, see what was deployed, check how a resource stands, see how long its operations usually take, " \
                 "and restart a compute for anything Neon runs, " \
                 "through the tools that are switched on. It also uses Neon's other tools that are switched on.", Capabilities.halon_sentence("neon", "Neon")
  end

  private

  test "run history is the operations Neon ran on the resource, each timed from when it was made by how long it took" do
    call = resolve(Capabilities::HISTORY, "resource" => "shop/main", "name" => "start_compute")
    assert_equal [ "list_operations", { "project_id" => "shop-123", "limit" => Capabilities::Neon::OPERATIONS_READ } ], [ call.tool.name, call.arguments ]

    operations = { "operations" => [
      { "id" => "op-3", "branch_id" => "br-main-1", "action" => "start_compute", "status" => "running", "created_at" => "2026-10-04T10:00:00Z" },
      { "id" => "op-2", "branch_id" => "br-main-1", "action" => "start_compute", "status" => "finished", "created_at" => "2026-10-04T09:00:00Z", "total_duration_ms" => 4000 },
      { "id" => "op-1", "branch_id" => "br-other-9", "action" => "start_compute", "status" => "failed", "created_at" => "2026-10-04T08:00:00Z", "total_duration_ms" => 1000 },
      { "id" => "op-0", "branch_id" => "br-main-1", "action" => "apply_config", "status" => "finished", "created_at" => "2026-10-04T07:00:00Z", "total_duration_ms" => 900 }
    ] }
    result = call.present_result({ "content" => [ { "type" => "text", "text" => operations.to_json } ] })

    assert_equal [ [ "op-3", "running", nil ], [ "op-2", "succeeded", 4 ] ], Capabilities::History.runs_of(result).map { |run| [ run.id, run.status, run.seconds ] }
    assert_match "Finished ones usually take 4 seconds", result["content"].first["text"]
  end

  def resolve(key, given) = Capabilities.resolve(@workspace, key, given, principal: map_reader)

  def unroutable(key, given) = assert_raises(Capabilities::Unroutable) { resolve(key, given) }.message

  def answer_text(call, body)
    call.present_result({ "content" => [ { "type" => "text", "text" => JSON.pretty_generate(body) } ] })["content"].first["text"]
  end
end
