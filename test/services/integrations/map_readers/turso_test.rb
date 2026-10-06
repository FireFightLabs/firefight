require "test_helper"

module Integrations
  module MapReaders
    class TursoTest < ActiveSupport::TestCase
      DATABASES = { "databases" => [
        { "Name" => "shop", "DbId" => "db-1", "Hostname" => "shop-acme.turso.io", "group" => "default", "primaryRegion" => "aws-us-east-1",
          "block_reads" => false, "block_writes" => false, "engine" => "libsql" },
        { "Name" => "shop-fix", "DbId" => "db-2", "group" => "default", "block_reads" => false, "block_writes" => true,
          "parent" => { "id" => "db-1", "name" => "shop" } }
      ] }.freeze

      test "databases go on the map, a branched one as a branch of its parent, with writes that are blocked said in its status" do
        snapshot = Turso.new { |tool, _arguments| tool == Turso::LIST_DATABASES ? result(DATABASES) : flunk("called #{tool}") }.map

        database, branch = snapshot.resources
        assert_equal [ "turso", "default", ResourceMap::KIND_DATABASE, "db-1" ], database.key
        assert_equal [ "shop", "active" ], [ database.name, database.status ]
        assert_equal({ "engine" => "libsql", "region" => "aws-us-east-1", "hostname" => "shop-acme.turso.io", "delete_protection" => nil }.compact, database.details)
        assert_equal [ ResourceMap::KIND_BRANCH, "writes blocked" ], [ branch.kind, branch.status ]
        assert_equal [ [ branch.key, database.key, ResourceMap::RELATION_BRANCH_OF ] ], snapshot.links.map { |link| [ link.from, link.to, link.relation ] }
      end

      test "a switched off tool or a refusal is a gap, and nothing is taken as gone" do
        off = Turso.new { |_tool, _arguments| nil }.map
        assert_match "list_databases is switched off", off.gaps.sole.text
        assert_equal [ ResourceMap::KIND_DATABASE, ResourceMap::KIND_BRANCH ], off.unread_kinds

        refused = Turso.new { |_tool, _arguments| { "isError" => true, "content" => [ { "type" => "text", "text" => "forbidden" } ] } }.map
        assert_equal [ "Turso refused to list the databases: forbidden." ], refused.gaps.map(&:text)
        assert_equal [ ResourceMap::KIND_DATABASE, ResourceMap::KIND_BRANCH ], refused.unread_kinds
      end

      test "a database is reached at its hostname on the HTTPS port, and one without a hostname has no address" do
        workspace = workspaces(:slack_workspace_one)
        settings = ConnectionSettings.of(workspace.integrations.build(kind: Integration::KIND_MCP, provider: Turso::PROVIDER).integration_environments.build)
        snapshot = Turso.new(settings) { |_tool, _arguments| result(DATABASES) }.map

        assert_equal [ [ snapshot.resources.first.key, ResourceMap::Fingerprint.of("shop-acme.turso.io", 443, workspace) ] ],
                     snapshot.endpoints.map { |endpoint| [ endpoint.resource, endpoint.fingerprint ] }
      end

      private

      def result(body) = { "content" => [ { "type" => "text", "text" => body.to_json } ] }
    end
  end
end
