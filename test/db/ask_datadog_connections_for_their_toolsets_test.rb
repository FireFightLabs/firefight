require "test_helper"
require Rails.root.join("db/migrate/20261011100000_ask_datadog_connections_for_their_toolsets")

class AskDatadogConnectionsForTheirToolsetsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "each Datadog connection keeps its own address and gains the toolsets, one that names toolsets is left alone, and it moves back" do
    eu = connection("Datadog EU", "datadog", "https://mcp.datadoghq.eu/v1/mcp", region: "eu1")
    unstable = connection("Datadog old", "datadog", "https://mcp.datadoghq.com/api/unstable/mcp-server/mcp")
    pasted = connection("Datadog proxy", "datadog", "https://dd.acme.example/v1/mcp?org=acme")
    chosen = connection("Datadog all", "datadog", "https://mcp.datadoghq.com/v1/mcp?toolsets=all")
    sentry = connection("Sentry", "sentry", "https://mcp.sentry.dev/mcp")

    migrate(:up)

    assert_equal "https://mcp.datadoghq.eu/v1/mcp?toolsets=core,error-tracking", eu.reload.server_url
    assert_equal "eu1", eu.region_key, "the rest of the connection's settings are kept"
    assert_equal "eu1", eu.region.key
    assert_equal "https://mcp.datadoghq.com/api/unstable/mcp-server/mcp?toolsets=core,error-tracking", unstable.reload.server_url
    assert_equal "https://dd.acme.example/v1/mcp?org=acme&toolsets=core,error-tracking", pasted.reload.server_url
    assert_equal "https://mcp.datadoghq.com/v1/mcp?toolsets=all", chosen.reload.server_url
    assert_equal "https://mcp.sentry.dev/mcp", sentry.reload.server_url
    assert_equal IntegrationProvider.find("datadog").region("eu1").server_url, eu.server_url, "a connection reads as a new one in its region would"

    migrate(:up)
    assert_equal "https://mcp.datadoghq.eu/v1/mcp?toolsets=core,error-tracking", eu.reload.server_url, "running it twice changes nothing"

    migrate(:down)
    assert_equal [ "https://mcp.datadoghq.eu/v1/mcp", "https://dd.acme.example/v1/mcp?org=acme", "https://mcp.datadoghq.com/v1/mcp?toolsets=all" ],
                 [ eu.reload.server_url, pasted.reload.server_url, chosen.reload.server_url ]
  end

  private

  def connection(name, provider, server_url, region: nil)
    @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: provider, name: name,
                                    settings: { "server_url" => server_url, Integration::REGION_SETTING => region }.compact)
  end

  def migrate(direction) = ActiveRecord::Migration.suppress_messages { AskDatadogConnectionsForTheirToolsets.new.migrate(direction) }
end
