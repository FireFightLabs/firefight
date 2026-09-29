require "test_helper"

module Integrations
  module MapReaders
    class PlanetscaleTest < ActiveSupport::TestCase
      ORGS = { "data" => [ { "name" => "acme" } ] }.freeze
      DATABASES = { "data" => [ { "name" => "shop", "state" => "ready", "kind" => "postgresql", "plan" => "scaler_pro",
                                  "html_url" => "https://app.planetscale.com/acme/shop", "region" => { "display_name" => "GCP us-east1" } } ] }.freeze
      BRANCHES = { "data" => [ { "name" => "main", "state" => "ready", "production" => true, "html_url" => "https://app.planetscale.com/acme/shop/main" } ] }.freeze

      test "every organization's databases and their branches go on the map, each branch linked to its database" do
        snapshot = Planetscale.new { |tool, _arguments| answer(tool) }.map

        database, branch = snapshot.resources
        assert_equal [ "planetscale", "acme", ResourceMap::KIND_DATABASE, "shop" ], database.key
        assert_equal({ "engine" => "postgresql", "plan" => "scaler_pro", "region" => "GCP us-east1" }, database.details)
        assert_equal [ "planetscale", "acme", ResourceMap::KIND_BRANCH, "shop/main" ], branch.key
        assert branch.details["production"]
        assert_equal [ [ branch.key, database.key, ResourceMap::RELATION_BRANCH_OF ] ], snapshot.links.map { |link| [ link.from, link.to, link.relation ] }
        assert_empty snapshot.gaps
      end

      test "a long list is read page by page" do
        asked = []
        snapshot = Planetscale.new do |tool, arguments|
          asked << [ tool, arguments.dig("queryParameters", "page") ]
          next answer(tool) unless tool == Planetscale::LIST_DATABASES

          page = arguments.dig("queryParameters", "page")
          result("data" => [ { "name" => "db#{page}" } ], "next_page" => (page < 2 ? page + 1 : nil))
        end.map

        assert_equal %w[db1 db2], snapshot.resources.select { |each| each.kind == ResourceMap::KIND_DATABASE }.map(&:external_id)
        assert_equal [ [ Planetscale::LIST_DATABASES, 1 ], [ Planetscale::LIST_DATABASES, 2 ] ], asked.select { |tool, _| tool == Planetscale::LIST_DATABASES }
      end

      test "a tool switched off, or a list PlanetScale refuses, is a gap in the map" do
        snapshot = Planetscale.new do |tool, _arguments|
          next nil if tool == Planetscale::LIST_BRANCHES
          next answer(tool) unless tool == Planetscale::LIST_DATABASES

          { "content" => [ { "type" => "text", "text" => "forbidden" } ], "isError" => true }
        end.map

        assert_equal [ "PlanetScale refused to list the databases in acme: forbidden" ], snapshot.gaps

        switched_off = Planetscale.new { |tool, _arguments| tool == Planetscale::LIST_BRANCHES ? nil : answer(tool) }.map
        assert_equal [ "planetscale_list_branches is switched off for PlanetScale, so the branches of shop are not on the map." ], switched_off.gaps
        assert_equal [ ResourceMap::KIND_DATABASE ], switched_off.resources.map(&:kind)
      end

      test "the sweep calls only the tools an admin switched on" do
        integration = workspaces(:slack_workspace_one).integrations.create!(
          kind: Integration::KIND_MCP, provider: "planetscale", name: "PlanetScale", settings: { "server_url" => "https://mcp.example/mcp" }
        )
        row = integration.integration_environments.create!(credentials: { authorization: "Bearer x" }.to_json)
        [ Planetscale::LIST_ORGANIZATIONS, Planetscale::LIST_DATABASES ].each { |name| integration.tools.create!(name: name, enabled: true) }
        integration.tools.create!(name: Planetscale::LIST_BRANCHES, enabled: false)
        McpClient.any_instance.expects(:call_tool).with { |name:, arguments:| name != Planetscale::LIST_BRANCHES }.twice
                 .returns(result(ORGS), result(DATABASES))

        snapshot = McpExecutor.map_of(row)

        assert_match "planetscale_list_branches is switched off", snapshot.gaps.sole
      end

      private

      def answer(tool) = result({ Planetscale::LIST_ORGANIZATIONS => ORGS, Planetscale::LIST_DATABASES => DATABASES, Planetscale::LIST_BRANCHES => BRANCHES }.fetch(tool))

      def result(body) = { "content" => [ { "type" => "text", "text" => body.to_json } ] }
    end
  end
end
