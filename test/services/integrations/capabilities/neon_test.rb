require "test_helper"

class Integrations::Capabilities::NeonTest < ActiveSupport::TestCase
  Capabilities = Integrations::Capabilities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    neon = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "neon", name: "Neon", slug: "neon", settings: { "server_url" => "https://mcp.neon.tech/mcp" })
    @row = neon.integration_environments.create!
    changes = %w[restart_postgres_endpoint start_postgres_endpoint update_postgres_endpoint restore_snapshot reset_from_parent restore_branch]
    Capabilities::Neon::TOOLS.values.flatten.uniq.each do |name|
      neon.tools.create!(name: name, description: name, read_only: changes.exclude?(name), enabled: true, params_schema: { "type" => "object" })
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
    assert_equal "Halon can read its logs, read a project's compute time and data sent out, see what was deployed, check how a resource stands, " \
                 "see how long its operations usually take, read its slowest queries, roll a branch back to a moment, a snapshot or its parent, " \
                 "restart a compute or start a suspended one, " \
                 "and resize a compute for anything Neon runs, through the tools that are switched on. It also uses Neon's other tools " \
                 "that are switched on.", Capabilities.halon_sentence("neon", "Neon")
  end

  test "a suspended compute is started rather than restarted, by the state the map has for it" do
    ResourceMap.record!(@row, ResourceMap::Snapshot.new(resources: [ @project, @branch, @compute.with(status: "sleeping") ]))
    call = resolve(Capabilities::RESTART, "resource" => "ep-cool-1")

    assert_equal [ "start_postgres_endpoint", { "project_id" => "shop-123", "endpoint_id" => "ep-cool-1" } ], [ call.tool.name, call.arguments ]
    assert call.spec.writes
    assert_match "Neon is starting ep-cool-1, which was suspended", answer_text(call, { "endpoint" => { "id" => "ep-cool-1" } })
  end

  test "a compute is resized to one size or an autoscaling range Neon offers, and copies are refused" do
    fixed = resolve(Capabilities::SCALE, "resource" => "ep-cool-1", "plan" => "2")
    assert_equal [ "update_postgres_endpoint", { "project_id" => "shop-123", "endpoint_id" => "ep-cool-1", "autoscaling_limit_min_cu" => 2.0,
                                                 "autoscaling_limit_max_cu" => 2.0 } ], [ fixed.tool.name, fixed.arguments ]
    assert fixed.spec.writes
    assert_match "Neon set ep-cool-1 to a fixed 2 CU. It restarts the compute to apply it", answer_text(fixed, { "endpoint" => { "id" => "ep-cool-1" } })

    ranged = resolve(Capabilities::SCALE, "resource" => "ep-cool-1", "plan" => "0.25 - 4")
    assert_equal [ 0.25, 4.0 ], ranged.arguments.values_at("autoscaling_limit_min_cu", "autoscaling_limit_max_cu")
    assert_match "autoscale between 0.25 and 4 CU", answer_text(ranged, {})
    assert_equal [ 20.0, 20.0 ], resolve(Capabilities::SCALE, "resource" => "ep-cool-1", "plan" => "20").arguments.values_at("autoscaling_limit_min_cu", "autoscaling_limit_max_cu")

    assert_match "leave instances out", unroutable(Capabilities::SCALE, "resource" => "ep-cool-1", "instances" => 2)
    assert_match "Neon offers no 1.5 CU compute", unroutable(Capabilities::SCALE, "resource" => "ep-cool-1", "plan" => "1.5")
    assert_match "at most 8 CU apart", unroutable(Capabilities::SCALE, "resource" => "ep-cool-1", "plan" => "1-10")
    assert_match "at most 8 CU apart", unroutable(Capabilities::SCALE, "resource" => "ep-cool-1", "plan" => "16-20")
    assert_match "smaller size goes first", unroutable(Capabilities::SCALE, "resource" => "ep-cool-1", "plan" => "4-1")
    assert_match "such as 0.25-4", unroutable(Capabilities::SCALE, "resource" => "ep-cool-1", "plan" => "large")
    assert_match "no connection offers scaling", unroutable(Capabilities::SCALE, "resource" => "shop/main", "plan" => "2")
  end

  test "errors are the slowest queries pg_stat_statements holds, for the project's default branch, a branch or one compute" do
    call = resolve(Capabilities::ERRORS, "resource" => "shop/main", "limit" => 5)
    assert_equal [ "list_slow_queries", { "project_id" => "shop-123", "limit" => 5, "branch_id" => "br-main-1" } ], [ call.tool.name, call.arguments ]
    assert_equal({ "project_id" => "shop-123", "limit" => 10 }, resolve(Capabilities::ERRORS, "resource" => "shop").arguments)
    assert_equal({ "project_id" => "shop-123", "limit" => 10, "compute_id" => "ep-cool-1" }, resolve(Capabilities::ERRORS, "resource" => "ep-cool-1").arguments)

    slow = { "slow_queries" => [ { "query" => "SELECT * FROM orders WHERE   user_id = $1", "calls" => 1200, "total_exec_time_ms" => 960_000.4,
                                   "mean_exec_time_ms" => 800.04, "rows" => 5000 },
                                 { "query" => "UPDATE carts SET total = $1", "calls" => 40, "total_exec_time_ms" => 8000, "mean_exec_time_ms" => 200 } ],
             "total_queries_found" => 2 }
    text = answer_text(call, slow)
    assert_match "The 2 slowest queries on shop/main by average time, from pg_stat_statements", text
    assert_match "800.0ms on average, 1200 calls, 960000ms in all, 5000 rows, SELECT * FROM orders WHERE user_id = $1", text
    searched = resolve(Capabilities::ERRORS, "resource" => "shop/main", "text" => "ORDERS", "limit" => 1)
    assert_equal 50, searched.arguments["limit"]
    assert_no_match "carts", answer_text(searched, slow)
    assert_match "SELECT * FROM orders", answer_text(searched, slow)
    assert_match "no slow queries containing payments among its 2 slowest", answer_text(resolve(Capabilities::ERRORS, "resource" => "shop/main", "text" => "payments"), slow)
    assert_match "pg_stat_statements holds no slow queries for shop/main", answer_text(call, { "slow_queries" => [] })
  end

  test "a function's status and deploys are its latest deployment and the one serving, read with get_function" do
    function = ResourceMap::Found.new(provider: "neon", account: "Acme", kind: ResourceMap::KIND_FUNCTION, external_id: "shop-123/br-main-1/hooks",
                                      name: "shop/main/hooks", url: "https://console.neon.tech/app/projects/shop-123/branches/br-main-1")
    ResourceMap.record!(@row, ResourceMap::Snapshot.new(resources: [ @project, @branch, @compute, function ]))
    body = { "function" => { "id" => "fn-1", "slug" => "hooks", "invocation_url" => "https://br-main-1-hooks.example.neon.tech/",
                             "current_deployment" => { "id" => 4, "status" => "failed", "error" => "build failed", "runtime" => "nodejs22",
                                                       "memory_mib" => 256, "created_at" => "2026-10-19T10:00:00Z" },
                             "active_deployment" => { "id" => 3, "status" => "completed", "runtime" => "nodejs22", "memory_mib" => 256,
                                                      "created_at" => "2026-10-18T10:00:00Z" } } }

    deploys = resolve(Capabilities::DEPLOYS, "resource" => "shop/main/hooks")
    assert_equal [ "get_function", { "project_id" => "shop-123", "branch_id" => "br-main-1", "slug" => "hooks" } ], [ deploys.tool.name, deploys.arguments ]
    result = deploys.present_result({ "content" => [ { "type" => "text", "text" => body.to_json } ] })
    assert_match "version 4, failed, 2026-10-19T10:00:00Z, nodejs22, 256 MiB, failed (build failed)\nversion 3, completed, serving", result["content"].first["text"]
    assert_equal [ [ "4", "failed", false ], [ "3", "succeeded", true ] ],
                 Capabilities::Deploys.deploys_of(result).map { |deploy| [ deploy.id, deploy.status, deploy.live ] }
    assert_equal "3", Capabilities::Deploys.live(Capabilities::Deploys.deploys_of(result)).id

    status = resolve(Capabilities::STATUS, "resource" => "shop/main/hooks")
    assert_equal "get_function", status.tool.name
    assert answer_text(status, body).start_with?("How shop/main/hooks stands on Neon now: serving version 3, latest version 4 failed, its latest build " \
                                                 "failed (build failed), invoked at https://br-main-1-hooks.example.neon.tech/.")
    assert_match "has no deployment yet", answer_text(deploys, { "function" => { "slug" => "hooks" } })
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

  test "one run asked by its id is read with get_operation, however old it is" do
    call = resolve(Capabilities::HISTORY, "resource" => "shop/main", "run" => "op-0")
    assert_equal [ "get_operation", { "project_id" => "shop-123", "operation_id" => "op-0" } ], [ call.tool.name, call.arguments ]

    operation = { "operation" => { "id" => "op-0", "branch_id" => "br-main-1", "action" => "apply_config", "status" => "failed",
                                   "error" => "compute did not start", "created_at" => "2026-09-01T07:00:00Z", "total_duration_ms" => 3000 } }
    runs = Capabilities::History.runs_of(call.present_result({ "content" => [ { "type" => "text", "text" => operation.to_json } ] }))

    assert_equal [ [ "op-0", "apply_config", "failed", 3, "compute did not start" ] ], runs.map { |run| [ run.id, run.name, run.status, run.seconds, run.detail ] }
  end

  test "a branch rolls back to a snapshot onto itself, finalized, or to its parent, and each is a change" do
    snapshot = resolve(Capabilities::ROLLBACK, "resource" => "shop/main", "to" => "snap-123")
    assert_equal [ "restore_snapshot", { "project_id" => "shop-123", "snapshot_id" => "snap-123", "target_branch_id" => "br-main-1", "finalize" => true } ],
                 [ snapshot.tool.name, snapshot.arguments ]
    assert snapshot.spec.writes
    assert_match "Neon restored snapshot snap-123 onto shop/main and moved its computes onto it", answer_text(snapshot, { "branch" => { "id" => "br-main-1" } })

    parent = resolve(Capabilities::ROLLBACK, "resource" => "shop/main", "to" => "Parent")
    assert_equal [ "reset_from_parent", { "project_id" => "shop-123", "branch_id" => "br-main-1" } ], [ parent.tool.name, parent.arguments ]
    assert_match "Neon reset shop/main to its parent's current state", answer_text(parent, { "branch" => { "id" => "br-main-1" } })

    assert_match "a snapshot's id, as list_snapshots gives it, or parent", unroutable(Capabilities::ROLLBACK, "resource" => "shop/main", "to" => " ")
    assert_match "no connection offers a rollback", unroutable(Capabilities::ROLLBACK, "resource" => "ep-cool-1", "to" => "parent")
  end

  test "a branch rolls back to its own state at a moment or an LSN through restore_branch, always keeping its current state" do
    travel_to Time.utc(2026, 10, 20, 15) do
      moment = resolve(Capabilities::ROLLBACK, "resource" => "shop/main", "to" => "2026-10-20T14:30:00Z")
      assert_equal [ "restore_branch", { "project_id" => "shop-123", "branch_id" => "br-main-1", "preserve_under_name" => "main-before-rollback-10201500",
                                         "source_timestamp" => "2026-10-20T14:30:00Z" } ], [ moment.tool.name, moment.arguments ]
      assert_equal "its current state as branch main-before-rollback-10201500", moment.keeps
      assert moment.spec.writes

      lsn = resolve(Capabilities::ROLLBACK, "resource" => "shop/main", "to" => "0/1A2B3C4")
      assert_equal "0/1A2B3C4", lsn.arguments["source_lsn"]
    end
  end

  test "a project's metrics are its compute time and data sent out from its consumption, and what it does not keep is named" do
    call = resolve(Capabilities::METRICS, "resource" => "shop", "minutes" => 120)
    assert_equal [ "consumption_history", { "project_id" => "shop-123", "metrics" => %w[compute_unit_seconds public_network_transfer_bytes], "minutes" => 120 } ],
                 [ call.tool.name, call.arguments ]
    assert_equal %w[compute_unit_seconds], resolve(Capabilities::METRICS, "resource" => "shop", "metrics" => [ "cpu_time" ]).arguments["metrics"]
    assert_match "Neon does not keep cpu for this resource. It keeps cpu_time, network_out.", unroutable(Capabilities::METRICS, "resource" => "shop", "metrics" => [ "cpu" ])
    assert_match "no connection offers metrics", unroutable(Capabilities::METRICS, "resource" => "shop/main")
  end

  test "a branch with children keeps its state as a named branch when it is reset, and the confirmation says so" do
    child = ResourceMap::Found.new(provider: "neon", account: "Acme", kind: ResourceMap::KIND_BRANCH, external_id: "shop-123/br-preview-2", name: "shop/preview",
                                   details: { Integrations::MapReaders::Neon::PARENT_DETAIL => "br-main-1" })
    ResourceMap.record!(@row, ResourceMap::Snapshot.new(resources: [ @project, @branch, @compute, child ]))

    travel_to Time.utc(2026, 10, 11, 15, 30) do
      parent = resolve(Capabilities::ROLLBACK, "resource" => "shop/main", "to" => "parent")
      assert_equal({ "project_id" => "shop-123", "branch_id" => "br-main-1", "preserve_under_name" => "main-before-rollback-10111530" }, parent.arguments)
      assert_equal "its current state as branch main-before-rollback-10111530", parent.keeps
      assert_match "Its state before is kept as branch main-before-rollback-10111530", answer_text(parent, { "branch" => { "id" => "br-main-1" } })

      tool = Chat::Tools::Capability.allocate
      assert_equal "branch shop/main on Neon, account Acme, keeping its current state as branch main-before-rollback-10111530", tool.send(:target_of, parent)
    end

    assert_nil resolve(Capabilities::ROLLBACK, "resource" => "shop/preview", "to" => "parent").keeps, "a branch with no children keeps nothing aside"
  end

  def resolve(key, given) = Capabilities.resolve(@workspace, key, given, principal: map_reader)

  def unroutable(key, given) = assert_raises(Capabilities::Unroutable) { resolve(key, given) }.message

  def answer_text(call, body)
    call.present_result({ "content" => [ { "type" => "text", "text" => JSON.pretty_generate(body) } ] })["content"].first["text"]
  end
end
