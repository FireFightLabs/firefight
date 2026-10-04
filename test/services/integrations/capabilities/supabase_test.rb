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
    Capabilities::Supabase::TOOLS.each_value do |name|
      @supabase.tools.create!(name: name, description: name, read_only: true, enabled: true, params_schema: name == "get_project" ? { "type" => "object" } : WITH_PROJECT)
    end
    ResourceMap.record!(@row, ResourceMap::Snapshot.new(resources: [
      ResourceMap::Found.new(provider: "supabase", account: "acme", kind: ResourceMap::KIND_DATABASE, external_id: REF, name: "shop",
                             url: "https://supabase.com/dashboard/project/#{REF}")
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
    assert_equal [ true, "Supabase could not read the logs: bad sql" ], [ failed["isError"], failed["content"].first["text"] ]
  end

  test "what Supabase cannot read is said" do
    assert_match "at most a day of logs", unroutable(Capabilities::LOGS, "resource" => "shop", "minutes" => 2000)
    assert_match "Postgres logs with stream app and the API requests", unroutable(Capabilities::LOGS, "resource" => "shop", "stream" => "build")
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

  private

  def resolve(key, given) = Capabilities.resolve(@workspace, key, given)

  def unroutable(key, given) = assert_raises(Capabilities::Unroutable) { resolve(key, given) }.message

  def answer_text(call, body) = call.present_result({ "content" => [ { "type" => "text", "text" => body.to_json } ] })["content"].first["text"]
end
