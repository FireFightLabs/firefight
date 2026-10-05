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

    test "a connection's site is its region's, or the provider's own for one that runs in one place, and an empty field is its default" do
      datadog = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "datadog", name: "Datadog",
                                                settings: { "server_url" => "https://mcp.datadoghq.eu/v1/mcp", "region" => "eu1" })
      assert_equal "https://app.datadoghq.eu", ConnectionSettings.of(datadog.integration_environments.create!).site

      acme = IntegrationProvider.find("linear").with(key: "acme", site: "https://app.acme.example", connect_fields: [
        IntegrationProvider::ConnectField.new(key: "limit", label: "Limit", hint: "At most.", default: "5")
      ])
      IntegrationProvider.stubs(:find).with("acme").returns(acme)
      row = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "acme", name: "Acme", settings: { "server_url" => "https://mcp.acme.example" })
                      .integration_environments.create!
      settings = ConnectionSettings.of(row)

      assert_equal [ "https://app.acme.example", "5" ], [ settings.site, settings.field(:limit) ]
      row.store_fields!("limit" => "8")
      assert_equal "8", ConnectionSettings.of(row.reload).field(:limit)
    end

    test "a connection knows every site its provider's regions have, and keeps a value its pack caches with the credentials" do
      datadog = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "datadog", name: "Datadog", settings: { "server_url" => "https://mcp.datadoghq.com/v1/mcp" })
      settings = ConnectionSettings.of(datadog.integration_environments.create!)

      assert_includes settings.region_sites, "https://app.datadoghq.eu"
      assert_equal IntegrationProvider.find("datadog").regions.size, settings.region_sites.size
      settings.store_credential!(:token_cache, { "token" => "t", "expires_at" => "2026-10-04T12:00:00Z" })
      assert_equal "t", ConnectionSettings.of(datadog.integration_environments.sole.reload).credential(:token_cache)["token"]
    end
  end
end
