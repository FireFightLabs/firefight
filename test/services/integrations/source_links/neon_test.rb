require "test_helper"

module Integrations
  module SourceLinks
    class NeonTest < ActiveSupport::TestCase
      setup do
        integration = Integration.new(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_MCP, provider: Neon::PROVIDER)
        @links = Neon.new(ConnectionSettings.of(integration.integration_environments.build))
      end

      test "a result links to the branch it named, or to its project, on Neon's console" do
        branch = @links.link(tool_name: "get_branch", arguments: { "project_id" => "shop-123", "branch_id" => "br-main-1" })
        project = @links.link(tool_name: "run_sql", arguments: { "project_id" => "shop-123", "sql" => "select 1" })

        assert_equal [ "Neon", "https://console.neon.tech/app/projects/shop-123/branches/br-main-1" ], [ branch.provider, branch.url ]
        assert_equal "https://console.neon.tech/app/projects/shop-123", project.url
      end

      test "a call that names no project, or an id Neon would never give, gets no link" do
        assert_nil @links.link(tool_name: "list_projects", arguments: {})
        assert_nil @links.link(tool_name: "describe_project", arguments: { "project_id" => "../../evil" })
      end
    end
  end
end
