require "test_helper"

module Integrations
  module SourceLinks
    class SupabaseTest < ActiveSupport::TestCase
      REF = "abcdefghijklmnopqrst".freeze

      setup do
        @links = Supabase.new(settings)
      end

      test "a result links to its project's dashboard, on the page its answer lives on" do
        assert_equal "https://supabase.com/dashboard/project/#{REF}/database/migrations", url("list_migrations", "project_id" => REF)
        assert_equal "https://supabase.com/dashboard/project/#{REF}/branches", url("list_branches", "project_id" => REF)
        assert_equal "https://supabase.com/dashboard/project/#{REF}/logs", url("query_logs", "project_id" => REF, "sql" => "select 1")
        assert_equal "https://supabase.com/dashboard/project/#{REF}/logs/postgres-logs", url("get_logs", "project_id" => REF, "service" => "postgres")
        assert_equal "https://supabase.com/dashboard/project/#{REF}/logs/edge-logs", url("get_logs", "project_id" => REF, "service" => "api")
        assert_equal "https://supabase.com/dashboard/project/#{REF}", url("get_project", "id" => REF)
        assert_equal "https://supabase.com/dashboard/project/#{REF}", url("execute_sql", "project_id" => REF, "query" => "select 1")
        assert_equal "Supabase, on its migrations page", @links.link(tool_name: "list_migrations", arguments: { "project_id" => REF }).provider
      end

      test "a connection scoped to one project links to that project" do
        scoped = Supabase.new(settings("project_ref" => REF, "read_only" => "true"))

        assert_equal "https://supabase.com/dashboard/project/#{REF}/database/migrations", scoped.link(tool_name: "list_migrations", arguments: {}).url
      end

      test "a call that names no project, or an organization's id, gets no link" do
        assert_nil @links.link(tool_name: "list_projects", arguments: {})
        assert_nil @links.link(tool_name: "get_organization", arguments: { "id" => "acme" })
      end

      private

      def settings(fields = {})
        integration = Integration.new(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_MCP, provider: Supabase::PROVIDER,
                                      settings: { "server_url" => "https://mcp.supabase.com/mcp", Integration::FIELDS_SETTING => fields })
        ConnectionSettings.of(integration.integration_environments.build)
      end

      def url(tool, arguments) = @links.link(tool_name: tool, arguments: arguments).url
    end
  end
end
