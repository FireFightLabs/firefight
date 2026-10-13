require "test_helper"

module Integrations
  class ToolDefinitionRecountJobTest < ActiveSupport::TestCase
    test "every connection's tools are counted again as a model is handed them, whatever was stored before" do
      workspace = workspaces(:slack_workspace_one)
      github = workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
      github.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id)
      github.integration_environments.create!(catalog_entry_id: catalog_entries(:development_env).id)
      runs = github.tools.create!(name: "list_runs", description: "Lists the runs.", params_schema: { "type" => "object" })
      sentry = workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "sentry", name: "Sentry", slug: "sentry",
                                              settings: { "server_url" => "https://mcp.example/mcp" })
      issues = sentry.tools.create!(name: "list_issues", description: "Lists issues.", params_schema: { "type" => "object" })
      Integration::Tool.where(id: [ runs.id, issues.id ]).update_all(definition_chars: 1)

      ToolDefinitionRecountJob.perform_now

      assert_equal runs.reload.definition_length, runs.definition_chars
      assert_operator runs.definition_chars, :>, 1
      assert_equal issues.reload.definition_length, issues.definition_chars
    end
  end
end
