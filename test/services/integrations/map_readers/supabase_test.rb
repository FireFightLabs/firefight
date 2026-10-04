require "test_helper"

module Integrations
  module MapReaders
    class SupabaseTest < ActiveSupport::TestCase
      PROJECTS = { "projects" => [ { "id" => "abcdefghijklmnopqrst", "ref" => "abcdefghijklmnopqrst", "organization_id" => "org1", "organization_slug" => "acme",
                                     "name" => "shop", "status" => "ACTIVE_HEALTHY", "region" => "us-east-1", "created_at" => "2026-01-01T00:00:00Z",
                                     "database" => { "version" => "15.8.1" } } ] }.freeze
      BRANCHES = { "branches" => [
        { "id" => "b1", "name" => "main", "project_ref" => "abcdefghijklmnopqrst", "parent_project_ref" => "abcdefghijklmnopqrst", "is_default" => true,
          "persistent" => true, "status" => "FUNCTIONS_DEPLOYED" },
        { "id" => "b2", "name" => "feature", "project_ref" => "zyxwvutsrqponmlkjihg", "parent_project_ref" => "abcdefghijklmnopqrst", "is_default" => false,
          "git_branch" => "feature/checkout", "persistent" => false, "status" => "MIGRATIONS_FAILED" }
      ] }.freeze

      test "every project is a database, and each branch is a project of its own linked to it" do
        snapshot = Supabase.new(settings) { |tool, _arguments| answer(tool) }.map

        project, main, feature = snapshot.resources
        assert_equal [ "supabase", "acme", ResourceMap::KIND_DATABASE, "abcdefghijklmnopqrst" ], project.key
        assert_equal [ "ACTIVE_HEALTHY", "https://supabase.com/dashboard/project/abcdefghijklmnopqrst" ], [ project.status, project.url ]
        assert_equal({ "engine" => "Postgres 15.8.1", "region" => "us-east-1" }, project.details)
        assert main.details[ResourceMap::PRODUCTION]
        assert_equal [ ResourceMap::KIND_BRANCH, "zyxwvutsrqponmlkjihg", "shop/feature", "MIGRATIONS_FAILED" ], [ feature.kind, feature.external_id, feature.name, feature.status ]
        assert_equal "https://supabase.com/dashboard/project/zyxwvutsrqponmlkjihg", feature.url
        assert_equal "feature/checkout", feature.details["branch"]
        assert_equal [ ResourceMap::RELATION_BRANCH_OF ] * 2, snapshot.links.map(&:relation)
        assert_equal ResourceMap::Resource::HEALTH_FAILING, ResourceMap::Resource.new(status: feature.status).health
        assert_equal ResourceMap::Resource::HEALTH_OK, ResourceMap::Resource.new(status: project.status).health
      end

      test "a list switched off, or one Supabase refuses, is a gap in the map" do
        off = Supabase.new { |tool, _arguments| tool == Supabase::LIST_PROJECTS ? nil : answer(tool) }.map
        assert_equal [ "list_projects is switched off for Supabase, or the connection is scoped to one project, so the projects are not on the map." ], off.gaps

        refused = Supabase.new do |tool, _arguments|
          tool == Supabase::LIST_BRANCHES ? { "isError" => true, "content" => [ { "type" => "text", "text" => "Failed to list branches" } ] } : answer(tool)
        end.map
        assert_equal [ "Supabase refused to list the branches of shop: Failed to list branches" ], refused.gaps
        assert_equal [ ResourceMap::KIND_DATABASE ], refused.resources.map(&:kind)
      end

      private

      def settings
        integration = Integration.new(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_MCP, provider: Supabase::PROVIDER)
        ConnectionSettings.of(integration.integration_environments.build)
      end

      def answer(tool) = { "content" => [ { "type" => "text", "text" => { Supabase::LIST_PROJECTS => PROJECTS, Supabase::LIST_BRANCHES => BRANCHES }.fetch(tool).to_json } ] }
    end
  end
end
