require "test_helper"

module Integrations
  class SourceLinksTest < ActiveSupport::TestCase
    setup do
      @workspace = workspaces(:slack_workspace_one)
    end

    test "every provider says how its results link back to their page, and a new one is never left unchecked" do
      IntegrationProvider.all.each do |provider|
        assert_includes IntegrationProvider::SOURCE_LINKS, provider.source_links, "#{provider.key} declares no source_links"
        if IntegrationProvider::SOURCE_LINKS_EXPLAINED.include?(provider.source_links)
          assert provider.source_links_note.present?, "#{provider.key} declares #{provider.source_links} without saying why"
        end
      end
      unchecked = IntegrationProvider.all.select { |provider| provider.source_links == IntegrationProvider::SOURCE_LINKS_UNCHECKED }.map(&:key)
      assert_equal %w[gitlab linear confluence], unchecked,
                   "A provider added since the rule was written has to check its links before it lands"
    end

    test "a remote provider that relies on Firefight for its links has a builder" do
      remote = IntegrationProvider.all.select { |provider| provider.kind == Integration::KIND_MCP && provider.source_links == IntegrationProvider::SOURCE_LINKS_FIREFIGHT }

      assert_equal remote.map(&:key).sort, Provider.all.select(&:source_links).map(&:key).sort
    end

    test "a declaration the rule does not know, or a server that does not say why, is refused when the registry loads" do
      assert_raises(ArgumentError) { IntegrationProvider.declared({ "key" => "acme", "source_links" => "sometimes" }, "source_links", IntegrationProvider::SOURCE_LINKS, IntegrationProvider::SOURCE_LINKS_EXPLAINED) }
      assert_raises(ArgumentError) { IntegrationProvider.declared({ "key" => "acme", "source_links" => IntegrationProvider::SOURCE_LINKS_SERVER }, "source_links", IntegrationProvider::SOURCE_LINKS, IntegrationProvider::SOURCE_LINKS_EXPLAINED) }
      assert_equal IntegrationProvider::SOURCE_LINKS_NONE,
                   IntegrationProvider.declared({ "key" => "acme", "source_links" => IntegrationProvider::SOURCE_LINKS_NONE, "source_links_note" => "No pages." },
                                                "source_links", IntegrationProvider::SOURCE_LINKS, IntegrationProvider::SOURCE_LINKS_EXPLAINED)
    end

    test "the executor adds the page to what a remote tool answered, and nothing to an error" do
      integration = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: SourceLinks::Cloudflare::PROVIDER, name: "Cloudflare",
                                                    settings: { "server_url" => "https://mcp.cloudflare.com/mcp" })
      row = integration.integration_environments.create!(credentials: { authorization: "Bearer x" }.to_json)
      tool = integration.tools.create!(name: SourceLinks::Cloudflare::EXECUTE, description: "Call the API", params_schema: {},
                                       spec: { "tool_name" => SourceLinks::Cloudflare::EXECUTE })
      McpClient.any_instance.stubs(:call_tool).returns({ "content" => [ { "type" => "text", "text" => '[{"zone_name":"firefight.app"}]' } ] })

      arguments = { "code" => "cloudflare.request({ path: `/zones/${id}/dns_records` })", "account_id" => "a" * 32 }
      result = McpExecutor.call(tool: tool, environment_row: row, arguments: arguments)

      assert_equal "Open this in Cloudflare, and give the person this link with what you found: " \
                   "https://dash.cloudflare.com/#{'a' * 32}/firefight.app/dns/records", result["content"].last["text"]

      McpClient.any_instance.stubs(:call_tool).returns({ "isError" => true, "content" => [ { "type" => "text", "text" => "403 Forbidden" } ] })
      assert_equal [ "403 Forbidden" ], McpExecutor.call(tool: tool, environment_row: row, arguments: arguments)["content"].map { |part| part["text"] }
    end

    test "a provider with no builder answers as it did" do
      result = { "content" => [ { "type" => "text", "text" => "ok" } ] }

      sentry = @workspace.integrations.build(kind: Integration::KIND_MCP, provider: "sentry", name: "Sentry")
      row = sentry.integration_environments.build

      assert_equal result, SourceLinks.attach(result, settings: ConnectionSettings.of(row), tool_name: "search_issues", arguments: {})
    end
  end
end
