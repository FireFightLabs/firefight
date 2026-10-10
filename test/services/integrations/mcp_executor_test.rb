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

    private

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
