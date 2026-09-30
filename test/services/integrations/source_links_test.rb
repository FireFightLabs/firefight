require "test_helper"

module Integrations
  class SourceLinksTest < ActiveSupport::TestCase
    setup do
      @workspace = workspaces(:slack_workspace_one)
    end

    test "every provider says how its results link back to their page, and a new one is never left unchecked" do
      IntegrationProvider.all.each do |provider|
        assert_includes IntegrationProvider::SOURCE_LINKS, provider.source_links, "#{provider.key} declares no source_links"
        assert provider.source_links_note.present?, "#{provider.key} says there is no page without saying why" if provider.source_links == IntegrationProvider::SOURCE_LINKS_NONE
      end
      unchecked = IntegrationProvider.all.select { |provider| provider.source_links == IntegrationProvider::SOURCE_LINKS_UNCHECKED }.map(&:key)
      assert_equal %w[gitlab newrelic datadog grafana sentry linear confluence neon supabase], unchecked,
                   "A provider added since the rule was written has to check its links before it lands"
    end

    test "a remote provider that relies on Firefight for its links has a builder" do
      remote = IntegrationProvider.all.select { |provider| provider.kind == Integration::KIND_MCP && provider.source_links == IntegrationProvider::SOURCE_LINKS_FIREFIGHT }

      assert_equal remote.map(&:key).sort, SourceLinks::BUILDERS.keys.sort
    end

    test "the executor adds the page to what a remote tool answered" do
      integration = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "cloudflare", name: "Cloudflare",
                                                    settings: { "server_url" => "https://mcp.cloudflare.com/mcp" })
      row = integration.integration_environments.create!(credentials: { authorization: "Bearer x" }.to_json)
      tool = integration.tools.create!(name: "execute", description: "Call the API", params_schema: {}, spec: { "tool_name" => "execute" })
      McpClient.any_instance.stubs(:call_tool).returns({ "content" => [ { "type" => "text", "text" => '[{"zone_name":"firefight.app"}]' } ] })

      result = McpExecutor.call(tool: tool, environment_row: row, arguments: { "code" => "cloudflare.request({ path: `/zones/${id}/dns_records` })",
                                                                                 "account_id" => "a" * 32 })

      assert_equal "Open this in Cloudflare, and give the person this link with what you found: " \
                   "https://dash.cloudflare.com/?to=/#{'a' * 32}/firefight.app/dns/records", result["content"].last["text"]
    end

    test "a provider with no builder answers as it did" do
      result = { "content" => [ { "type" => "text", "text" => "ok" } ] }

      assert_equal result, SourceLinks.attach(result, provider: "sentry", workspace: @workspace, tool_name: "search_issues", arguments: {})
    end
  end
end
