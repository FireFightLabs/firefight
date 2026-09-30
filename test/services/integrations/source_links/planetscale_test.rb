require "test_helper"

module Integrations
  module SourceLinks
    class PlanetscaleTest < ActiveSupport::TestCase
      setup do
        @workspace = workspaces(:slack_workspace_one)
        row = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: Planetscale::PROVIDER, name: "PlanetScale", slug: "planetscale",
                                              settings: { "server_url" => "https://mcp.pscale.dev/mcp/planetscale" }).integration_environments.create!
        found = ->(kind, id, url) { ResourceMap::Found.new(provider: Planetscale::PROVIDER, account: "acme", kind: kind, external_id: id, name: id, url: url) }
        ResourceMap.record!(row, ResourceMap::Snapshot.new(resources: [
          found.(ResourceMap::KIND_DATABASE, "shop", "https://app.planetscale.com/acme/shop"),
          found.(ResourceMap::KIND_BRANCH, "shop/main", "https://app.planetscale.com/acme/shop/main")
        ]))
        @links = Planetscale.new(@workspace)
      end

      test "a result links to the branch it read, on the tab that shows it, at the address PlanetScale gave" do
        link = @links.link(tool_name: Planetscale::GET_INSIGHTS, arguments: { "organization" => "acme", "database" => "shop", "branch" => "main" })

        assert_equal "https://app.planetscale.com/acme/shop/main", link.url
        assert_equal "PlanetScale, on the Insights tab", link.provider
      end

      test "a tool that names its place in path parameters, or only a database, links there" do
        schema = @links.link(tool_name: "planetscale_get_branch_schema", arguments: { "pathParameters" => { "organization" => "acme", "database" => "shop", "branch" => "main" } })
        advice = @links.link(tool_name: "planetscale_list_schema_recommendations", arguments: { "pathParameters" => { "organization" => "acme", "database" => "shop" } })

        assert_equal [ "https://app.planetscale.com/acme/shop/main", "PlanetScale" ], [ schema.url, schema.provider ]
        assert_equal "https://app.planetscale.com/acme/shop", advice.url
      end

      test "no link is made up for a place the map has not seen" do
        assert_nil @links.link(tool_name: Planetscale::GET_INSIGHTS, arguments: { "organization" => "acme", "database" => "billing", "branch" => "main" })
        assert_nil @links.link(tool_name: "planetscale_list_organizations", arguments: {})
      end
    end
  end
end
