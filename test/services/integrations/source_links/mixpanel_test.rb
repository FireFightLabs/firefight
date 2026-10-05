require "test_helper"

module Integrations
  module SourceLinks
    class MixpanelTest < ActiveSupport::TestCase
      setup do
        @integration = Integration.new(workspace: workspaces(:slack_workspace_one), provider: "mixpanel", kind: Integration::KIND_MCP,
                                       settings: { "server_url" => "https://mcp-eu.mixpanel.com/mcp", "region" => "eu" })
      end

      test "the one page on the region's site an answer names becomes the link" do
        text = "Created board. Open it at https://eu.mixpanel.com/project/3018488/view/3536632/app/boards#id=7198653."
        link = links.link(tool_name: "create_dashboard", arguments: {}, text: text)

        assert_equal [ "Mixpanel", "https://eu.mixpanel.com/project/3018488/view/3536632/app/boards#id=7198653" ], [ link.provider, link.url ]
        repeated = "{\"url\":\"https://eu.mixpanel.com/project/1/view/2/app/insights#abc\",\"again\":\"https://eu.mixpanel.com/project/1/view/2/app/insights#abc\"}"
        assert_equal "https://eu.mixpanel.com/project/1/view/2/app/insights#abc", links.link(tool_name: "get_report", arguments: {}, text: repeated).url
      end

      test "every region reads pages on its own site, and not another region's" do
        IntegrationProvider.find("mixpanel").regions.each do |region|
          @integration.settings = { "server_url" => region.server_url, "region" => region.key }
          page = "#{region.site}/project/1/view/2/app/boards#id=3"

          assert_equal page, links.link(tool_name: "get_dashboard", arguments: {}, text: page).url, region.key
        end
        @integration.settings = { "server_url" => "https://mcp.mixpanel.com/mcp", "region" => "us" }
        assert_nil links.link(tool_name: "get_dashboard", arguments: {}, text: "https://eu.mixpanel.com/project/1/view/2/app/boards#id=3")
      end

      test "several pages, none, or a server in no region gets no link" do
        several = "https://eu.mixpanel.com/project/1/view/2/app/boards#id=1 and https://eu.mixpanel.com/project/1/view/2/app/boards#id=2"

        assert_nil links.link(tool_name: "list_dashboards", arguments: {}, text: several)
        assert_nil links.link(tool_name: "run_query", arguments: {}, text: "{\"series\":{}}")
        @integration.settings = { "server_url" => "https://example.com/mcp" }
        assert_nil links.link(tool_name: "get_dashboard", arguments: {}, text: "https://mixpanel.com/project/1/view/2/app/boards#id=3")
      end

      private

      def links = Mixpanel.new(ConnectionSettings.of(@integration.integration_environments.build))
    end
  end
end
