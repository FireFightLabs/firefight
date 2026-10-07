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
        assert_empty snapshot.gap_texts
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

        assert_equal [ "PlanetScale refused to list the databases in acme: forbidden." ], snapshot.gap_texts

        switched_off = Planetscale.new { |tool, _arguments| tool == Planetscale::LIST_BRANCHES ? nil : answer(tool) }.map
        assert_equal [ "planetscale_list_branches is switched off for PlanetScale, so the branches of shop are not on the map." ], switched_off.gap_texts
        assert_equal [ ResourceMap::KIND_DATABASE ], switched_off.resources.map(&:kind)
      end

      test "an answer in a shape the reader does not know is a gap naming the list's kinds, never an empty list" do
        snapshot = Planetscale.new { |tool, _arguments| tool == Planetscale::LIST_DATABASES ? result({ "databases" => [] }) : answer(tool) }.map

        assert_empty snapshot.resources
        assert_equal [ "PlanetScale answered the databases in acme in a shape Firefight does not read." ], snapshot.gap_texts
        assert_includes snapshot.unread_kinds, ResourceMap::KIND_DATABASE

        bare = Planetscale.new { |tool, _arguments| tool == Planetscale::LIST_DATABASES ? result(DATABASES["data"]) : answer(tool) }.map
        assert_equal [ ResourceMap::KIND_DATABASE, ResourceMap::KIND_BRANCH ], bare.resources.map(&:kind)
      end

      test "the sweep calls only the tools that are switched on" do
        integration = workspaces(:slack_workspace_one).integrations.create!(
          kind: Integration::KIND_MCP, provider: "planetscale", name: "PlanetScale", settings: { "server_url" => "https://mcp.example/mcp" }
        )
        row = integration.integration_environments.create!(credentials: { authorization: "Bearer x" }.to_json)
        [ Planetscale::LIST_ORGANIZATIONS, Planetscale::LIST_DATABASES ].each { |name| integration.tools.create!(name: name, enabled: true) }
        integration.tools.create!(name: Planetscale::LIST_BRANCHES, enabled: false)
        McpClient.any_instance.expects(:call_tool).with { |name:, arguments:| name != Planetscale::LIST_BRANCHES }.twice
                 .returns(result(ORGS), result(DATABASES))

        snapshot = McpExecutor.map_of(row)

        assert_match "planetscale_list_branches is switched off", snapshot.gap_texts.sole
      end

      test "a Postgres branch is matched by its domain and the branch id in the user's name, a MySQL production branch by its shared address and database" do
        workspace = workspaces(:slack_workspace_one)
        integration = workspace.integrations.build(kind: Integration::KIND_MCP, provider: Planetscale::PROVIDER)
        settings = ConnectionSettings.of(integration.integration_environments.build)
        branches = { "data" => [ { "id" => "wmqh5ngwvupj", "name" => "main", "kind" => "postgresql", "production" => true } ] }
        postgres = Planetscale.new(settings) { |tool, _| tool == Planetscale::LIST_BRANCHES ? result(branches) : answer(tool) }.map

        assert_equal [ 5432, 6432 ], postgres.endpoints.map(&:port)
        assert postgres.endpoints.all?(&:within_domain)
        use = ResourceMap::Use.of(%w[web], "DATABASE_URL", "postgresql://postgres.wmqh5ngwvupj:pscale_pw_x@abc-useast1-1.horizon.psdb.cloud:5432/shop", workspace)
        assert_equal [ use.domain_fingerprint, use.tenant_fingerprint ], postgres.endpoints.first.then { |endpoint| [ endpoint.fingerprint, endpoint.tenant_fingerprint ] }

        mysql = { "data" => [ { "id" => "b1", "name" => "main", "kind" => "mysql", "production" => true, "mysql_address" => "aws.connect.psdb.cloud" },
                              { "id" => "b2", "name" => "dev", "kind" => "mysql", "production" => false, "mysql_address" => "aws.connect.psdb.cloud" } ] }
        shared = Planetscale.new(settings) { |tool, _| tool == Planetscale::LIST_BRANCHES ? result(mysql) : answer(tool) }.map
        endpoint = shared.endpoints.sole
        assert_equal [ "planetscale", "acme", ResourceMap::KIND_BRANCH, "shop/main" ], endpoint.resource
        assert_equal [ true, 3306, ResourceMap::Fingerprint.of_name("shop", workspace) ], [ endpoint.shared_host, endpoint.port, endpoint.database_fingerprint ]
      end

      test "a re-read of one branch reads it and its database with the tools for each, and finds it gone only when PlanetScale says not found" do
        tools = { Planetscale::GET_DATABASE => true, Planetscale::GET_BRANCH => true, Planetscale::LIST_BRANCHES => true }
        asked = []
        reader = Planetscale.new(nil, tools) do |tool, arguments|
          asked << [ tool, arguments["pathParameters"] ]
          tool == Planetscale::GET_BRANCH ? result(BRANCHES["data"].first.merge("state" => "sleeping")) : result(DATABASES["data"].first)
        end
        snapshot = reader.map(scope: ResourceMap::Scope.new(account: "acme", kind: ResourceMap::KIND_BRANCH, external_id: "shop/main"))

        assert_equal [ [ Planetscale::GET_DATABASE, { "organization" => "acme", "database" => "shop" } ],
                       [ Planetscale::GET_BRANCH, { "organization" => "acme", "database" => "shop", "branch" => "main" } ] ], asked
        database, branch = snapshot.resources
        assert_equal [ [ "planetscale", "acme", ResourceMap::KIND_DATABASE, "shop" ], [ "planetscale", "acme", ResourceMap::KIND_BRANCH, "shop/main" ] ], [ database.key, branch.key ]
        assert_equal "sleeping", branch.status
        assert_equal [ [ branch.key, database.key ] ], snapshot.links.map { |link| [ link.from, link.to ] }

        not_found = { "content" => [ { "type" => "text", "text" => { "code" => "not_found", "message" => "Not Found" }.to_json } ], "isError" => true }
        gone = Planetscale.new(nil, tools) { |tool, _arguments| tool == Planetscale::GET_BRANCH ? not_found : result(DATABASES["data"].first) }
                          .map(scope: ResourceMap::Scope.new(account: "acme", kind: ResourceMap::KIND_BRANCH, external_id: "shop/dev"))
        assert_equal [ [ "planetscale", "acme", ResourceMap::KIND_BRANCH, "shop/dev" ] ], gone.gone

        refused = { "content" => [ { "type" => "text", "text" => { "code" => "forbidden", "message" => "Forbidden" }.to_json } ], "isError" => true }
        error = assert_raises(Integrations::Error) do
          Planetscale.new(nil, tools) { |_tool, _arguments| refused }.map(scope: ResourceMap::Scope.new(account: "acme", kind: ResourceMap::KIND_DATABASE, external_id: "shop"))
        end
        assert_match "PlanetScale refused to read the database shop", error.message
      end

      test "a re-read of a database reads its branches as the sweep does, and a scope it cannot narrow to, or a tool switched off, is left to a sweep" do
        tools = { Planetscale::GET_DATABASE => true, Planetscale::LIST_BRANCHES => true }
        snapshot = Planetscale.new(nil, tools) { |tool, _arguments| tool == Planetscale::GET_DATABASE ? result(DATABASES["data"].first) : answer(tool) }
                              .map(scope: ResourceMap::Scope.new(account: "acme", kind: ResourceMap::KIND_DATABASE, external_id: "shop"))
        assert_equal %w[shop shop/main], snapshot.resources.map(&:external_id)

        assert_nil Planetscale.new(nil, tools) { |tool, _arguments| answer(tool) }.map(scope: ResourceMap::Scope.new(account: "acme"))
        assert_nil Planetscale.new(nil, tools) { |tool, _arguments| answer(tool) }
                              .map(scope: ResourceMap::Scope.new(account: "acme", kind: ResourceMap::KIND_BRANCH, external_id: "shop/main"))
      end

      private

      def answer(tool) = result({ Planetscale::LIST_ORGANIZATIONS => ORGS, Planetscale::LIST_DATABASES => DATABASES, Planetscale::LIST_BRANCHES => BRANCHES }.fetch(tool))

      def result(body) = { "content" => [ { "type" => "text", "text" => body.to_json } ] }
    end
  end
end
