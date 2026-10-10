require "test_helper"

class Conversation::Watches::ReaderTest < ActiveSupport::TestCase
  History = Integrations::Capabilities::History

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    planetscale = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "planetscale", name: "PlanetScale", slug: "planetscale",
                                                  settings: { "server_url" => "https://mcp.pscale.dev/mcp/planetscale" })
    @environment_row = planetscale.integration_environments.create!
    @read = planetscale.tools.create!(name: "planetscale_execute_read_query", description: "Runs a read", read_only: true, enabled: true,
                                      params_schema: { "type" => "object", "properties" => { "use_replica" => { "type" => "boolean" } } })
    @sent = []
    Integrations::McpExecutor.stubs(:call).with { |arguments:, **| @sent << arguments }.returns("content" => [ { "type" => "text", "text" => "1" } ])
    @reader = Conversation::Watches::Reader.new(workspace: @workspace, principal: @alice, conversation: @conversation)
  end

  test "a capability read a watch makes goes to the primary unless the call asked for a replica" do
    @reader.read_call(routed("query" => "select 1"))
    @reader.read_call(routed("query" => "select 2", "use_replica" => true))

    assert_equal [ { "query" => "select 1", "use_replica" => false }, { "query" => "select 2", "use_replica" => true } ], @sent
  end

  test "a run's log a watch reads goes to the primary unless the run asked for a replica" do
    @reader.read_log(@environment_row, History::LOG_TOOL => @read.name, History::LOG_ARGUMENTS => { "query" => "select 1" })
    @reader.read_log(@environment_row, History::LOG_TOOL => @read.name, History::LOG_ARGUMENTS => { "query" => "select 2", "use_replica" => true })

    assert_equal [ { "query" => "select 1", "use_replica" => false }, { "query" => "select 2", "use_replica" => true } ], @sent
  end

  private

  def routed(arguments)
    stub(tool: @read, scope: {}, arguments: arguments, environment_row: @environment_row, fallback: nil,
         present_result: { "content" => [ { "type" => "text", "text" => "1" } ] })
  end
end
