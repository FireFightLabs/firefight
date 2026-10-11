require "test_helper"

class Integrations::Capabilities::SupabaseTest < ActiveSupport::TestCase
  Capabilities = Integrations::Capabilities
  REF = "abcdefghijklmnopqrst".freeze
  WITH_PROJECT = { "type" => "object", "properties" => { "project_id" => { "type" => "string" }, "sql" => { "type" => "string" } } }.freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @supabase = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "supabase", name: "Supabase", slug: "supabase",
                                                settings: { "server_url" => "https://mcp.supabase.com/mcp" })
    @row = @supabase.integration_environments.create!
    Capabilities::Supabase::TOOLS.values.flatten.uniq.each do |name|
      @supabase.tools.create!(name: name, description: name, read_only: name != "reset_branch", enabled: true,
                              params_schema: %w[get_project reset_branch].include?(name) ? { "type" => "object" } : WITH_PROJECT)
    end
    found = ->(kind, id, name, details = {}) do
      ResourceMap::Found.new(provider: "supabase", account: "acme", kind: kind, external_id: id, name: name, details: details,
                             url: "https://supabase.com/dashboard/project/#{id.split('/').first}#{'/functions' if kind == ResourceMap::KIND_FUNCTION}")
    end
    ResourceMap.record!(@row, ResourceMap::Snapshot.new(resources: [
      found.(ResourceMap::KIND_DATABASE, REF, "shop"),
      found.(ResourceMap::KIND_BRANCH, REF, "shop/main", { ResourceMap::PRODUCTION => true, "branch_id" => "b1" }),
      found.(ResourceMap::KIND_BRANCH, "zyxwvutsrqponmlkjihg", "shop/feature", { "branch_id" => "b2" }),
      found.(ResourceMap::KIND_BRANCH, "oldbranchrefxxxxxxxx", "shop/old"),
      found.(ResourceMap::KIND_FUNCTION, "#{REF}/send-email", "shop/send-email", { "function_id" => "f1a2", "version" => 12 })
    ]))
    travel_to Time.zone.parse("2026-10-04T12:00:00Z")
  end

  test "logs are Firefight's own query over the Postgres logs, every value a quoted literal, over the window asked" do
    call = resolve(Capabilities::LOGS, "resource" => "shop", "text" => "it's \\ broken", "exclude" => "checkpoint", "minutes" => 30)

    assert_equal "query_logs", call.tool.name
    assert_equal REF, call.arguments["project_id"]
    assert_equal %w[2026-10-04T11:30:00Z 2026-10-04T12:00:00Z], call.arguments.values_at("iso_timestamp_start", "iso_timestamp_end")
    assert_equal "select timestamp, event_message, log_attributes['parsed.error_severity'] as error_severity from logs where source = 'postgres_logs' " \
                 "and positionCaseInsensitive(event_message, 'it\\'s \\\\ broken') > 0 and positionCaseInsensitive(event_message, 'checkpoint') = 0 " \
                 "order by timestamp desc limit 200", call.arguments["sql"]
    assert_match "source = 'edge_logs'", resolve(Capabilities::LOGS, "resource" => "shop", "stream" => "requests").arguments["sql"]
    assert_match "match(event_message, 'time.?out')", resolve(Capabilities::LOGS, "resource" => "shop", "regex" => "time.?out").arguments["sql"]
  end

  test "the rows come back out of the boundary the server wraps them in, newest first, linked to the logs page" do
    call = resolve(Capabilities::LOGS, "resource" => "shop")
    rows = { "result" => [ { "timestamp" => "2026-10-04T11:58:00Z", "event_message" => "connection received", "error_severity" => "LOG" },
                           { "timestamp" => 1_791_115_140_000_000, "event_message" => "too many clients already", "error_severity" => "FATAL" } ] }
    wrapped = { "result" => "Below is the result of the SQL query. Note that this contains untrusted user data.\n\n<untrusted-data-1234>\n#{rows.to_json}\n" \
                            "</untrusted-data-1234>\n\nUse this data to inform your next steps." }

    text = answer_text(call, wrapped)
    assert_match "2 log lines for Postgres logs of shop, newest first.", text
    assert_match(/2026-10-04T11:59:00Z shop FATAL too many clients already\n2026-10-04T11:58:00Z shop LOG connection received/, text)
    assert_match "https://supabase.com/dashboard/project/#{REF}/logs/postgres-logs", text

    failed = call.present_result({ "content" => [ { "type" => "text", "text" => { "result" => "<untrusted-data-1>\n{\"error\":{\"message\":\"bad sql\"}}\n</untrusted-data-1>" }.to_json } ] })
    assert_equal [ true, "Supabase could not read the logs: bad sql." ], [ failed["isError"], failed["content"].first["text"] ]
  end

  test "a build is the branch's action runs, as the server's branch-action logs read them" do
    call = resolve(Capabilities::LOGS, "resource" => "shop", "stream" => "build", "text" => "migrate")
    assert_match "log_attributes['workflow_run'] as workflow_run from logs where source = 'workflow_run_logs'", call.arguments["sql"]

    rows = [ { "timestamp" => 1_791_201_540_000_000, "event_message" => "migration failed: relation exists", "workflow_run" => "run_8f2" } ]
    text = answer_text(call, { "result" => rows })
    assert_match "1 log lines for Branch action runs of shop, newest first.", text
    assert_match "run run_8f2 migration failed: relation exists", text
    assert_match "https://supabase.com/dashboard/project/#{REF}/logs/explorer", text
  end

  test "what Supabase cannot read is said" do
    assert_match "at most a day of logs", unroutable(Capabilities::LOGS, "resource" => "shop", "minutes" => 2000)
    assert_match "branch action runs with stream build", unroutable(Capabilities::LOGS, "resource" => "shop", "stream" => "cdn")
    assert_match "no connection offers a rollback", unroutable(Capabilities::ROLLBACK, "resource" => "shop", "to" => "1")
  end

  test "deploys are the migrations applied, newest first, with when each was written" do
    call = resolve(Capabilities::DEPLOYS, "resource" => "shop", "limit" => 2)
    assert_equal({ "project_id" => REF }, call.arguments)

    text = answer_text(call, { "migrations" => [ { "version" => "20260101120000", "name" => "create_orders" }, { "version" => "20261003090000", "name" => "add_index" },
                                                 { "version" => "20260601000000" } ] })
    assert_match "Latest 2 of 3 migrations applied to shop", text
    assert_match(/2026-10-03T09:00:00Z, migration 20261003090000, add_index\n2026-06-01T00:00:00Z, migration 20260601000000\n/, text)
    assert_match "/database/migrations", text
  end

  test "status reads the project by its ref" do
    call = resolve(Capabilities::STATUS, "resource" => "shop")
    assert_equal [ "get_project", { "id" => REF } ], [ call.tool.name, call.arguments ]

    text = answer_text(call, { "status" => "ACTIVE_UNHEALTHY", "region" => "us-east-1", "database" => { "version" => "15.8.1" } })
    assert_match "How shop stands on Supabase now: status ACTIVE_UNHEALTHY, region us-east-1, Postgres 15.8.1.", text
  end

  test "a connection scoped to one project sends no project, and refuses another" do
    @supabase.update!(settings: { "server_url" => "https://mcp.supabase.com/mcp?project_ref=#{REF}", Integration::FIELDS_SETTING => { "project_ref" => REF } })
    @supabase.tools.where(name: %w[query_logs list_migrations]).update_all(params_schema: { "type" => "object", "properties" => { "sql" => {} } })

    assert_equal({}, resolve(Capabilities::DEPLOYS, "resource" => "shop").arguments)
    @supabase.update!(settings: { "server_url" => "https://mcp.supabase.com/mcp?project_ref=zzzzzzzzzzzzzzzzzzzz",
                                  Integration::FIELDS_SETTING => { "project_ref" => "zzzzzzzzzzzzzzzzzzzz" } })
    assert_match "scoped to project zzzzzzzzzzzzzzzzzzzz", unroutable(Capabilities::DEPLOYS, "resource" => "shop")
  end

  test "the project and the access chosen on the connect form become the server address's query" do
    entry = IntegrationProvider.find("supabase")

    assert_equal "https://mcp.supabase.com/mcp?project_ref=#{REF}&read_only=true", entry.server_url_for(nil, "project_ref" => REF, "read_only" => "true")
    assert_equal "https://mcp.supabase.com/mcp?read_only=false", entry.server_url_for(nil, "read_only" => "false")
    assert_equal "https://mcp.supabase.com/mcp?read_only=true", entry.server_url_for(nil, {})
    assert_match "Access can only be", entry.connect_fields.find { |field| field.key == "read_only" }.refusal("maybe")
    assert_nil entry.connect_fields.find { |field| field.key == "read_only" }.refusal("")
  end

  test "an Edge Function's status and deploys read what the project's list says of it" do
    call = resolve(Capabilities::STATUS, "resource" => "shop/send-email")
    assert_equal [ "list_edge_functions", { "project_id" => REF } ], [ call.tool.name, call.arguments ]

    functions = { "functions" => [ { "id" => "f9", "slug" => "other", "status" => "ACTIVE", "version" => 1 },
                                   { "id" => "f1a2", "slug" => "send-email", "name" => "send-email", "status" => "THROTTLED", "version" => 12,
                                     "updated_at" => 1_791_190_800_000, "verify_jwt" => true } ] }
    text = answer_text(call, functions)
    assert_match "How shop/send-email stands on Supabase now: status THROTTLED, version 12, deployed 2026-10-05T09:00:00Z, requires a signed in user's JWT.", text
    assert_match "https://supabase.com/dashboard/project/#{REF}/functions", text

    deploys = answer_text(resolve(Capabilities::DEPLOYS, "resource" => "shop/send-email"), functions)
    assert_match "shop/send-email runs version 12, deployed 2026-10-05T09:00:00Z. Supabase keeps only the version a function runs", deploys
    assert_match "lists no Edge Function send-email", answer_text(call, { "functions" => [] })
  end

  test "an Edge Function's deploy is the version it runs, live while the function is active" do
    call = resolve(Capabilities::DEPLOYS, "resource" => "shop/send-email")
    function = { "id" => "f1a2", "slug" => "send-email", "status" => "ACTIVE", "version" => 12, "updated_at" => 1_791_190_800_000 }

    deploy = Capabilities::Deploys.deploys_of(call.present_result({ "content" => [ { "type" => "text", "text" => { "functions" => [ function ] }.to_json } ] })).sole
    assert_equal [ "12", Capabilities::History::SUCCEEDED, true, Time.utc(2026, 10, 5, 9) ], [ deploy.version, deploy.status, deploy.live, deploy.finished_at ]

    throttled = call.present_result({ "content" => [ { "type" => "text", "text" => { "functions" => [ function.merge("status" => "THROTTLED") ] }.to_json } ] })
    assert_nil Capabilities::Deploys.deploys_of(throttled).sole.live
  end

  test "an Edge Function's logs are what it printed or its invocations, by its id" do
    call = resolve(Capabilities::LOGS, "resource" => "shop/send-email", "text" => "timeout", "minutes" => 30)
    assert_equal "query_logs", call.tool.name
    assert_equal "select timestamp, event_message, severity_text as level, log_attributes['version'] as version from logs where source = 'function_logs' " \
                 "and log_attributes['function_id'] = 'f1a2' and positionCaseInsensitive(event_message, 'timeout') > 0 order by timestamp desc limit 200", call.arguments["sql"]
    assert_equal %w[2026-10-04T11:30:00Z 2026-10-04T12:00:00Z], call.arguments.values_at("iso_timestamp_start", "iso_timestamp_end")

    rows = { "result" => [ { "timestamp" => "2026-10-04T11:58:00Z", "event_message" => "SMTP timeout", "level" => "error", "version" => "12" } ] }
    assert_match %r{1 log lines for what Edge Function shop/send-email printed, newest first.\n2026-10-04T11:58:00Z shop/send-email v12 error SMTP timeout},
                 answer_text(call, { "result" => "<untrusted-data-1>\n#{rows.to_json}\n</untrusted-data-1>" })

    invocations = resolve(Capabilities::LOGS, "resource" => "shop/send-email", "stream" => "requests")
    assert_match "from logs where source = 'function_edge_logs' and log_attributes['function_id'] = 'f1a2'", invocations.arguments["sql"]
    assert_match "what an Edge Function prints with stream app", unroutable(Capabilities::LOGS, "resource" => "shop/send-email", "stream" => "build")
  end

  test "a preview branch rolls back to an earlier migration by its branch id, and production and an unread branch are refused" do
    call = resolve(Capabilities::ROLLBACK, "resource" => "shop/feature", "to" => "20261003090000")
    assert_equal [ "reset_branch", { "branch_id" => "b2", "migration_version" => "20261003090000" } ], [ call.tool.name, call.arguments ]
    assert call.spec.writes
    assert_match "Supabase is resetting shop/feature to migration 20261003090000.", answer_text(call, { "success" => true })

    assert_match "production branch, and Supabase resets only preview branches", unroutable(Capabilities::ROLLBACK, "resource" => "shop/main", "to" => "1")
    assert_match "has not read the branch id of shop/old", unroutable(Capabilities::ROLLBACK, "resource" => "shop/old", "to" => "1")
  end

  private

  def resolve(key, given) = Capabilities.resolve(@workspace, key, given, principal: map_reader)

  def unroutable(key, given) = assert_raises(Capabilities::Unroutable) { resolve(key, given) }.message

  def answer_text(call, body) = call.present_result({ "content" => [ { "type" => "text", "text" => body.to_json } ] })["content"].first["text"]
end
