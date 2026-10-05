require "test_helper"

module Integrations
  module SourceLinks
    class ClickhouseTest < ActiveSupport::TestCase
      ORGANIZATION = "6b3a2f1e-0000-4000-8000-000000000001".freeze

      setup do
        integration = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_MCP, provider: "clickhouse", name: "ClickHouse",
                                                                            settings: { "server_url" => "https://mcp.clickhouse.cloud/mcp" })
        @settings = ConnectionSettings.of(integration.integration_environments.create!)
      end

      test "an organization's cost links to its billing page on the registry's console, and nothing without a documented page links" do
        builder = Clickhouse.new(@settings)

        link = builder.link(tool_name: "get_organization_cost", arguments: { "organizationId" => ORGANIZATION })
        assert_equal [ "the ClickHouse Cloud console", "https://console.clickhouse.cloud/organizations/#{ORGANIZATION}/billing" ], [ link.provider, link.url ]
        assert_nil builder.link(tool_name: "get_organization_cost", arguments: { "organizationId" => "../services" })
        assert_nil builder.link(tool_name: "get_service_details", arguments: { "organizationId" => ORGANIZATION, "serviceId" => "svc" })
      end
    end
  end
end
