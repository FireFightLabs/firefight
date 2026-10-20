require "test_helper"

class Integrations::Capabilities::TursoTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    turso = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "turso", name: "Turso", slug: "turso",
                                            settings: { "server_url" => "https://mcp.turso.ai/mcp" })
    @row = turso.integration_environments.create!
    @tool = turso.tools.create!(name: "get_database", description: "Database", read_only: true, enabled: true,
                                params_schema: { "type" => "object", "properties" => { "database" => { "type" => "string" } } })
    ResourceMap::Resource.create!(workspace: @workspace, provider: "turso", account: "default", kind: ResourceMap::KIND_DATABASE,
                                  external_id: "0eb771dd", name: "shop", integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  test "status names the database by the parameter the connected tool reports" do
    call = Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::STATUS, { "resource" => "shop" }, principal: map_reader)

    assert_equal [ @row, "get_database", { "database" => "shop" } ], [ call.environment_row, call.tool.name, call.arguments ]
    assert_equal [ Integrations::Capabilities::STATUS, Integrations::Capabilities::ERRORS, Integrations::Capabilities::ROLLBACK ], Integrations::Capabilities::Turso.capabilities
  end

  test "errors are the database's top queries through database_analytics, and a range asked is said to be the tool's own" do
    @row.integration.tools.create!(name: "database_analytics", description: "Analytics", read_only: true, enabled: true,
                                   params_schema: { "type" => "object", "properties" => { "database_name" => { "type" => "string" } } })
    errors = Integrations::Capabilities::ERRORS

    call = Integrations::Capabilities.resolve(@workspace, errors, { "resource" => "shop" }, principal: map_reader)
    assert_equal [ "database_analytics", { "database_name" => "shop" }, nil ], [ call.tool.name, call.arguments, call.present ]

    call = Integrations::Capabilities.resolve(@workspace, errors, { "resource" => "shop", "minutes" => 30 }, principal: map_reader)
    shaped = call.present_result("content" => [ { "type" => "text", "text" => "SELECT * FROM orders, 1200 runs" } ])
    assert_equal "Turso does not publish how database_analytics takes a time range, so these are shop's top queries over the tool's own default " \
                 "range, not the range asked.\nSELECT * FROM orders, 1200 runs", shaped["content"].first["text"]
    error = { "isError" => true, "content" => [ { "type" => "text", "text" => "no such database" } ] }
    assert_equal error, call.present_result(error)

    call = Integrations::Capabilities.resolve(@workspace, errors, { "resource" => "shop", "text" => "orders", "limit" => 3 }, principal: map_reader)
    text = call.present_result("content" => [ { "type" => "text", "text" => "rows" } ])["content"].first["text"]
    assert_match "takes no text to filter by, so these are all of its top queries, not only those containing orders.", text
    assert_match "takes no limit Firefight knows, so these are as many as it gives, which may be more than 3.", text
  end

  test "a rollback makes a new database from this one as it was at the moment asked, leaving it as it is" do
    branch = @row.integration.tools.create!(name: "create_branch", description: "Branch", read_only: false, enabled: true,
                                            params_schema: { "type" => "object", "properties" => { "database_name" => {}, "branch_name" => {}, "timestamp" => {} } })
    rollback = Integrations::Capabilities::ROLLBACK

    travel_to Time.utc(2026, 10, 20, 15, 0) do
      call = Integrations::Capabilities.resolve(@workspace, rollback, { "resource" => "shop", "to" => "2026-10-20T14:30:00Z" }, principal: map_reader)
      assert_equal [ "create_branch", { "database_name" => "shop", "branch_name" => "shop-restored-20261020143000", "timestamp" => "2026-10-20T14:30:00Z" } ],
                   [ call.tool.name, call.arguments ]
      assert_equal "shop as it is now, untouched, beside the restored copy shop-restored-20261020143000", call.keeps
      text = call.present_result("content" => [ { "type" => "text", "text" => "{}" } ])["content"].first["text"]
      assert_match "shop itself is unchanged, so check the data in shop-restored-20261020143000 and then point the application at it", text

      error = assert_raises(Integrations::Capabilities::Unroutable) do
        Integrations::Capabilities.resolve(@workspace, rollback, { "resource" => "shop", "to" => "yesterday" }, principal: map_reader)
      end
      assert_match "as an ISO 8601 time", error.message
      error = assert_raises(Integrations::Capabilities::Unroutable) do
        Integrations::Capabilities.resolve(@workspace, rollback, { "resource" => "shop", "to" => "2026-10-20T14:30:00" }, principal: map_reader)
      end
      assert_match "with Z or an offset", error.message
      assert_raises(Integrations::Capabilities::Unroutable) do
        Integrations::Capabilities.resolve(@workspace, rollback, { "resource" => "shop", "to" => "2026-10-21T00:00:00Z" }, principal: map_reader)
      end
    end

    branch.update!(params_schema: { "type" => "object", "properties" => { "database_name" => {}, "branch_name" => {} } })
    error = assert_raises(Integrations::Capabilities::Unroutable) do
      Integrations::Capabilities.resolve(@workspace, rollback, { "resource" => "shop", "to" => "2026-10-01T00:00:00Z" }, principal: map_reader)
    end
    assert_match "restore it with Turso's own tool", error.message
  end

  test "a tool that takes the database some other way is refused in words, and its own tool stays offered" do
    @tool.update!(params_schema: { "type" => "object", "properties" => { "target" => {} } })

    error = assert_raises(Integrations::Capabilities::Unroutable) { Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::STATUS, { "resource" => "shop" }, principal: map_reader) }
    assert_match "ask it with Turso's own tool", error.message
    assert_not Integrations::Capabilities::Turso.wraps?("get_database")
  end
end
