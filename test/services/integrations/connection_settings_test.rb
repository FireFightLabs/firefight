require "test_helper"

module Integrations
  class ConnectionSettingsTest < ActiveSupport::TestCase
    setup do
      @workspace = workspaces(:slack_workspace_one)
    end

    test "a connection's region is the one it was made in, or the one its pasted address is in, and a native one without a choice is in the first" do
      datadog = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "datadog", name: "Datadog",
                                                settings: { "server_url" => "https://mcp.datadoghq.eu/v1/mcp", "region" => "ap1" })
      assert_equal "ap1", ConnectionSettings.of(datadog.integration_environments.create!).region.key

      datadog.update!(settings: { "server_url" => "https://mcp.datadoghq.eu/v1/mcp" })
      assert_equal "eu1", ConnectionSettings.of(datadog.integration_environments.sole).region.key

      linear = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "linear", name: "Linear", settings: { "server_url" => "https://mcp.linear.app/mcp" })
      assert_nil ConnectionSettings.of(linear.integration_environments.create!).region
    end

    test "what the form asked and what the check learned are read from the row, never from its columns by provider code" do
      integration = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "sentry", name: "Sentry",
                                                    settings: { "server_url" => "https://mcp.sentry.dev/mcp/acme", "fields" => { "organization" => "acme" } })
      row = integration.integration_environments.create!(credentials: { "api_token" => "secret" }.to_json)
      row.store_fields!("account" => "42", "regions" => %w[us eu])
      row.store_learned!("sources" => [ "logs" ])

      settings = ConnectionSettings.of(row.reload)
      assert_equal [ "acme", "42", nil ], [ settings.field(:organization), settings.field("account"), settings.field("missing") ]
      assert_equal({ "sources" => [ "logs" ] }, settings.learned)
      assert_equal [ %w[us eu], "secret", nil ], [ settings.field(:regions), settings.credential(:api_token), settings.credential("missing") ]
      assert_equal [ @workspace, "sentry", "Sentry", "https://mcp.sentry.dev/mcp/acme" ], [ settings.workspace, settings.provider_key, settings.name, settings.server_url ]
    end
  end
end
