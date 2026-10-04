require "test_helper"

module Integrations
  module SourceLinks
    class NewrelicTest < ActiveSupport::TestCase
      GUID = "MTIzNDU2N3xBUE18QVBQTElDQVRJT058OTg3NjU0".freeze

      setup do
        @integration = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_MCP, provider: "newrelic", name: "New Relic",
                                                                            settings: { "server_url" => "https://mcp.newrelic.com/mcp/", "region" => "us" })
        @row = @integration.integration_environments.create!
      end

      test "an NRQL answer about one entity links to that entity's page, on the connection's region" do
        link = links.link(tool_name: "execute_nrql_query", text: rows(GUID, GUID))

        assert_equal "New Relic", link.provider
        assert_equal "https://one.newrelic.com/redirect/entity/#{GUID}", link.url
        @integration.update!(settings: { "server_url" => "https://mcp.eu.newrelic.com/mcp/", "region" => "eu" })
        assert_equal "https://one.eu.newrelic.com/redirect/entity/#{GUID}", links.link(tool_name: "execute_nrql_query", text: rows(GUID)).url
        @integration.update!(settings: { "server_url" => "https://mcp.jp.newrelic.com/mcp/" })
        assert_equal "https://one.jp.newrelic.com/redirect/entity/#{GUID}", links.link(tool_name: "execute_nrql_query", text: rows(GUID)).url
      end

      test "an answer naming no entity or several, another tool, a server in no region or an address that is not a GUID gets no link" do
        builder = links

        assert_nil builder.link(tool_name: "execute_nrql_query", text: { "results" => [ { "count" => 3 } ] }.to_json)
        assert_nil builder.link(tool_name: "execute_nrql_query", text: rows(GUID, "#{GUID}AA"))
        assert_nil builder.link(tool_name: "execute_nrql_query", text: rows("../../admin"))
        assert_nil builder.link(tool_name: "get_entity", text: rows(GUID))
        assert_nil builder.link(tool_name: "execute_nrql_query", text: "12 log lines")
        @integration.update!(settings: { "server_url" => "https://example.com/mcp" })
        assert_nil links.link(tool_name: "execute_nrql_query", text: rows(GUID))
      end

      private

      def links = Newrelic.new(Integrations::ConnectionSettings.of(@row.reload))

      def rows(*guids) = { "data" => { "results" => guids.map { |guid| { "message" => "boom", "entity.guid" => guid } } } }.to_json
    end
  end
end
