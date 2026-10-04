require "test_helper"

module Integrations
  module MapReaders
    class NeonTest < ActiveSupport::TestCase
      ORGANIZATIONS = [ { "id" => "org-acme-1", "name" => "Acme" } ].freeze
      PROJECTS = [ { "id" => "shop-123", "name" => "shop", "org_id" => "org-acme-1", "org_name" => "Acme", "pg_version" => 17, "region_id" => "aws-us-east-2" } ].freeze
      BRANCHES = [
        { "id" => "br-main-1", "name" => "main", "current_state" => "ready", "default" => true, "protected" => true, "logical_size" => 1024,
          "updated_at" => "2026-10-01T10:00:00Z" },
        { "id" => "br-preview-2", "name" => "preview", "current_state" => "ready", "default" => false, "protected" => false,
          "updated_at" => "2026-10-02T10:00:00Z" }
      ].freeze
      ENDPOINTS = [ { "id" => "ep-cool-1", "branch_id" => "br-main-1", "type" => "read_write", "current_state" => "idle", "host" => "ep-cool-1.us-east-2.aws.neon.tech",
                      "autoscaling_limit_min_cu" => 0.25, "autoscaling_limit_max_cu" => 2, "disabled" => false } ].freeze
      DATABASES = [ { "id" => 1, "name" => "neondb", "owner_name" => "neondb_owner" } ].freeze

      test "every project is a database, with its branches, the computes serving them and the databases on each" do
        snapshot = Neon.new(settings) { |tool, _arguments| answer(tool) }.map

        project, main, preview, compute = snapshot.resources
        assert_equal [ "neon", "Acme", ResourceMap::KIND_DATABASE, "shop-123" ], project.key
        assert_equal "https://console.neon.tech/app/projects/shop-123", project.url
        assert_equal({ "engine" => "Postgres 17", "region" => "aws-us-east-2" }, project.details)
        assert_equal [ ResourceMap::KIND_BRANCH, "shop-123/br-main-1", "shop/main", "ready" ], [ main.kind, main.external_id, main.name, main.status ]
        assert_equal "https://console.neon.tech/app/projects/shop-123/branches/br-main-1", main.url
        assert main.details[ResourceMap::PRODUCTION]
        assert_equal "neondb", main.details["databases"]
        assert_equal false, preview.details[ResourceMap::PRODUCTION]
        assert_equal [ ResourceMap::KIND_COMPUTE, "shop-123/ep-cool-1", "ep-cool-1", "idle" ], [ compute.kind, compute.external_id, compute.name, compute.status ]
        assert_equal({ "type" => "read_write", "branch" => "main", "host" => "ep-cool-1.us-east-2.aws.neon.tech", "autoscaling" => "0.25 to 2 CU" }, compute.details)
        assert_equal [ [ main.key, project.key, ResourceMap::RELATION_BRANCH_OF ], [ preview.key, project.key, ResourceMap::RELATION_BRANCH_OF ],
                       [ main.key, compute.key, ResourceMap::RELATION_SERVED_BY ] ], snapshot.links.map { |link| [ link.from, link.to, link.relation ] }
        assert_empty snapshot.gaps
      end

      test "each organization's projects are listed by its id, and without the organization list Neon picks the one there is" do
        asked = []
        Neon.new { |tool, arguments| asked << [ tool, arguments ] && answer(tool) }.map
        assert_equal [ { "limit" => Neon::PROJECT_LIMIT, "org_id" => "org-acme-1" } ], asked.select { |tool, _| tool == Neon::LIST_PROJECTS }.map(&:last)

        asked.clear
        Neon.new { |tool, arguments| asked << [ tool, arguments ] && (tool == Neon::LIST_ORGANIZATIONS ? nil : answer(tool)) }.map
        assert_equal [ { "limit" => Neon::PROJECT_LIMIT } ], asked.select { |tool, _| tool == Neon::LIST_PROJECTS }.map(&:last)
      end

      test "a tool switched off, or a list Neon refuses, is a gap in the map" do
        snapshot = Neon.new do |tool, _arguments|
          next nil if tool == Neon::LIST_COMPUTES
          next { "content" => [ { "type" => "text", "text" => "branch_not_found" } ], "isError" => true } if tool == Neon::LIST_DATABASES

          answer(tool)
        end.map

        assert_includes snapshot.gaps, "list_postgres_endpoints is switched off for Neon, so the computes of shop are not on the map."
        assert_includes snapshot.gaps, "Neon refused to list the databases on shop/main: branch_not_found"
        assert_equal [ ResourceMap::KIND_DATABASE, ResourceMap::KIND_BRANCH, ResourceMap::KIND_BRANCH ], snapshot.resources.map(&:kind)
      end

      test "only the default and latest branches have their databases read, and the rest is said" do
        branches = (1..(Neon::DATABASE_READS + 2)).map { |index| { "id" => "br-#{index}", "name" => "b#{index}", "default" => index == 1, "updated_at" => "2026-10-01T00:00:#{format('%02d', index)}Z" } }
        read = []
        snapshot = Neon.new do |tool, arguments|
          read << arguments["branch_id"] if tool == Neon::LIST_DATABASES
          tool == Neon::LIST_BRANCHES ? result(branches) : answer(tool)
        end.map

        assert_equal Neon::DATABASE_READS, read.size
        assert_equal "br-1", read.first
        assert_includes read, "br-#{Neon::DATABASE_READS + 2}"
        assert_includes snapshot.gaps, "The databases on 2 more branches of shop were not read, only on its default and latest #{Neon::DATABASE_READS}."
      end

      private

      def settings
        integration = Integration.new(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_MCP, provider: Neon::PROVIDER)
        ConnectionSettings.of(integration.integration_environments.build)
      end

      def answer(tool)
        result({ Neon::LIST_ORGANIZATIONS => ORGANIZATIONS, Neon::LIST_PROJECTS => PROJECTS, Neon::LIST_BRANCHES => BRANCHES,
                 Neon::LIST_COMPUTES => ENDPOINTS, Neon::LIST_DATABASES => DATABASES }.fetch(tool))
      end

      def result(body) = { "content" => [ { "type" => "text", "text" => JSON.pretty_generate(body) } ] }
    end
  end
end
