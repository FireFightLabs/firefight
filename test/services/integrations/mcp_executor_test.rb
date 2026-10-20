require "test_helper"

module Integrations
  class McpExecutorTest < ActiveSupport::TestCase
    setup do
      @workspace = workspaces(:slack_workspace_one)
      @planetscale = connection("planetscale", "PlanetScale", "https://mcp.pscale.dev/mcp/planetscale")
      @read = @planetscale.tools.create!(name: "planetscale_execute_read_query", description: "Runs a read", read_only: true, enabled: true, params_schema: {})
      Credentials.stubs(:headers_for).returns({})
    end

    test "a database read is given fifteen seconds in all, and running out says the provider was slow and what to do instead" do
      client = mock("client")
      client.expects(:call_tool).raises(McpClient::Error.new("mcp.pscale.dev did not answer within 15 seconds").extend(TimedOut))
      McpClient.expects(:new).with { |within:, **| within == McpExecutor::QUICK_READ }.returns(client)

      error = assert_raises(Integrations::Error) { call(@read) }

      assert_not_kind_of TimedOut, error
      assert_equal "PlanetScale did not answer within 15 seconds, so Firefight stopped waiting. Try the same read once more, " \
                   "narrowed if it reads a lot. If it is slow again, get what you need another way, such as the schema in the " \
                   "application's repository, another of PlanetScale's tools, or a read replica where the tool offers one, and " \
                   "say in your answer that PlanetScale was slow and what you did instead.", error.message
    end

    test "a server's own error words lose credentials before they reach the model, as an answer's do" do
      client = mock("client")
      client.expects(:call_tool).raises(McpClient::Error.new("MCP error: cannot open DATABASE_URL=postgres://app:s3cret@db.internal/app"))
      McpClient.stubs(:new).returns(client)

      error = assert_raises(McpClient::Error) { call(@read) }

      assert_equal "MCP error: cannot open DATABASE_URL=[REDACTED:credential_url]db.internal/app", error.message
    end

    test "a database read that answers in time comes back as it always did" do
      client = mock("client")
      client.expects(:call_tool).with(name: "planetscale_execute_read_query", arguments: { "query" => "select 1" })
            .returns("content" => [ { "type" => "text", "text" => "1" } ])
      McpClient.expects(:new).with { |within:, **| within == McpExecutor::QUICK_READ }.returns(client)

      assert_equal "1", call(@read, "query" => "select 1")["content"].first["text"]
    end

    test "a change, or a read from a provider that is not a database, keeps the usual wait and its own words" do
      write = @planetscale.tools.create!(name: "planetscale_create_branch", description: "Creates a branch", read_only: false, enabled: true, params_schema: {})
      notion = connection("notion", "Notion", "https://mcp.notion.com/mcp")
      search = notion.tools.create!(name: "notion_search", description: "Searches", read_only: true, enabled: true, params_schema: {})

      [ write, search ].each do |tool|
        client = mock("client")
        client.expects(:call_tool).raises(McpClient::Error.new("could not reach the server (Net::ReadTimeout)").extend(TimedOut))
        McpClient.expects(:new).with { |within:, **| within.nil? }.returns(client)

        error = assert_raises(McpClient::Error) { call(tool) }
        assert_equal "could not reach the server (Net::ReadTimeout)", error.message
      end
    end

    test "a server the registry names is called unchecked, and a pasted or custom one is checked against its provider's allowlist" do
      sentry = connection("sentry", "Sentry", "https://mcp.sentry.dev/mcp/acme")
      pasted = connection("datadog", "Our Datadog", "https://mcp.acme.example/datadog")
      custom = connection("custom_mcp", "Acme tools", "https://tools.acme.example/mcp")
      checked = {}
      McpClient.stubs(:new).with { |server_url:, checked_for:, **| checked.store(server_url, checked_for) || true }.returns(stub(tools_list: []))

      [ @planetscale, sentry, pasted, custom ].each { |integration| McpExecutor.tool_definitions(integration) }

      assert_equal({ "https://mcp.pscale.dev/mcp/planetscale" => nil, "https://mcp.sentry.dev/mcp/acme" => nil,
                     "https://mcp.acme.example/datadog" => "datadog", "https://tools.acme.example/mcp" => "custom_mcp" }, checked)
    end

    test "a pack beside the server adds the tools the connection is offered, keeps its own over a server tool of the same name, and runs them itself" do
      server = [ { "name" => "list_projects", "inputSchema" => { "type" => "object" } }, { "name" => "restart_project", "description" => "the server's own" } ]
      McpClient.stubs(:new).returns(stub(tools_list: server))
      supabase = connection("supabase", "Supabase", "https://mcp.supabase.com/mcp")

      names = McpExecutor.tool_definitions(supabase).map(&:name)
      assert_equal 1, names.count("restart_project")
      assert_includes names, "list_action_runs"
      assert_not_includes names, "restore_to_point_in_time", "a connection left read only, the connect form's default, is offered no change"
      restart = McpExecutor.tool_definitions(supabase.tap { |each| each.update!(settings: each.settings.merge(Integration::FIELDS_SETTING => { "read_only" => "false" })) })
                           .find { |definition| definition.name == "restart_project" }
      assert_equal [ false, true ], [ restart.read_only, restart.spec[Provider::FIREFIGHT_TOOL] ]

      tool = supabase.tools.create!(name: "get_project_health", description: "health", read_only: true, enabled: true, params_schema: {}, spec: { Provider::FIREFIGHT_TOOL => true })
      Packs::Supabase.any_instance.expects(:call).with("get_project_health", environment_row: supabase.integration_environments.first, arguments: { "project_id" => "abc" })
                     .returns(Telemetry.result("healthy", link: nil))
      McpClient.expects(:new).never
      assert_equal "healthy", call(tool, { "project_id" => "abc" })["content"].sole["text"]
      assert_equal "Shows how a project and each of its services stand now.", tool.summary

      restart_tool = supabase.tools.create!(name: "restart_project", description: "restart", read_only: false, enabled: true, params_schema: {},
                                            spec: { Provider::FIREFIGHT_TOOL => true })
      supabase.update!(settings: supabase.settings.merge(Integration::FIELDS_SETTING => { "read_only" => "true" }))
      Packs::Supabase.any_instance.expects(:call).with("restart_project", anything).never
      error = assert_raises(PolicyRefusal) { call(restart_tool.reload) }
      assert_match "restart_project is not offered on Supabase as it is set up now", error.message

      server_tool = supabase.tools.create!(name: "list_action_runs", description: "The server's own runs. More words.", read_only: true, enabled: true,
                                           params_schema: {}, spec: { "tool_name" => "list_action_runs" })
      assert_equal "The server's own runs.", server_tool.summary, "a server tool keeps its own words beside a pack tool of the same name"
    end

    private

    test "a provider's named tools join the server's, and each runs as the one general call Firefight writes, linked by it" do
      cloudflare = connection("cloudflare", "Cloudflare", "https://mcp.cloudflare.com/mcp")
      McpClient.stubs(:new).returns(stub(tools_list: [ { "name" => "execute", "inputSchema" => {} }, { "name" => "search", "inputSchema" => {} } ]))
      assert_equal %w[execute search retry_pages_deployment cancel_workers_build split_worker_traffic], McpExecutor.tool_definitions(cloudflare).map(&:name)

      account = "0123456789abcdef0123456789abcdef"
      retry_tool = cloudflare.tools.create!(name: "retry_pages_deployment", description: "Runs it again", read_only: false, enabled: true, params_schema: {})
      client = mock("client")
      client.expects(:call_tool).with do |name:, arguments:|
        name == "execute" && arguments["account_id"] == account &&
          arguments["code"].include?(%({"method":"POST","path":"/accounts/#{account}/pages/projects/docs/deployments/d2a1-4b/retry"}))
      end.returns("content" => [ { "type" => "text", "text" => %({"success":true,"result":{"id":"d3"}}) } ])
      McpClient.stubs(:new).returns(client)

      result = call(retry_tool, "account_id" => account, "project" => "docs", "deployment" => "d2a1-4b")

      assert_match "Pages deployment d2a1-4b of docs is running again as a new deployment.", result["content"].first["text"]
      assert_match "https://dash.cloudflare.com/#{account}/pages/view/docs/d2a1-4b", result["content"].last["text"]
      assert_match "project must be", assert_raises(Integrations::Error) { call(retry_tool, "account_id" => account, "project" => "../zones", "deployment" => "d2a1-4b") }.message
    end

    def connection(provider, name, server_url)
      integration = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: provider, name: name, slug: provider,
                                                    settings: { "server_url" => server_url })
      integration.integration_environments.create!
      integration
    end

    def call(tool, arguments = {})
      McpExecutor.call(tool: tool, environment_row: tool.integration.integration_environments.first, arguments: arguments)
    end
  end
end
