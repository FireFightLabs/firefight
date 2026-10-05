require "test_helper"

module Integrations
  module SourceLinks
    class PosthogTest < ActiveSupport::TestCase
      setup do
        @integration = Integration.new(workspace: workspaces(:slack_workspace_one), provider: "posthog", kind: Integration::KIND_MCP,
                                       settings: { "server_url" => "https://mcp-eu.posthog.com/mcp?mode=tools", "region" => "eu" })
      end

      test "the page PostHog's answer names at its top level becomes the link, from TOON text or JSON" do
        toon = "id: 5\nkey: new-checkout\nactive: false\n_posthogUrl: \"https://eu.posthog.com/project/7/feature_flags/5\""
        link = links.link(tool_name: "feature_flag_disable", arguments: { "id" => 5 }, text: toon)

        assert_equal [ "PostHog", "https://eu.posthog.com/project/7/feature_flags/5" ], [ link.provider, link.url ]
        json = { "results" => [], "_posthogUrl" => "https://eu.posthog.com/project/7/error_tracking" }.to_json
        assert_equal "https://eu.posthog.com/project/7/error_tracking", links.link(tool_name: "query_error_tracking_issues_list", arguments: {}, text: json).url
      end

      test "a page on any of PostHog's region sites is linked, since the US server signs an account in wherever it lives" do
        IntegrationProvider.find("posthog").regions.each do |connected|
          @integration.settings = { "server_url" => connected.server_url, "region" => connected.key }
          IntegrationProvider.find("posthog").regions.each do |region|
            page = "#{region.site}/project/7/feature_flags/5"
            assert_equal page, links.link(tool_name: "feature_flag_get_definition", arguments: {}, text: "_posthogUrl: \"#{page}\"").url, "#{connected.key} links #{region.key}"
          end
        end
      end

      test "a page inside a row, one off PostHog's sites, or an answer without one gets no link" do
        nested = "results[1]:\n  - id: 5\n    _posthogUrl: \"https://eu.posthog.com/project/7/feature_flags/5\""

        assert_nil links.link(tool_name: "feature_flag_get_all", arguments: {}, text: nested)
        assert_nil links.link(tool_name: "feature_flag_get_all", arguments: {}, text: "_posthogUrl: \"https://posthog.example.com/project/7\"")
        assert_nil links.link(tool_name: "feature_flag_get_all", arguments: {}, text: "_posthogUrl: \"https://eu.posthog.com.example.com/project/7\"")
        assert_nil links.link(tool_name: "query_logs", arguments: {}, text: "results: []")
      end

      private

      def links = Posthog.new(ConnectionSettings.of(@integration.integration_environments.build))
    end
  end
end
