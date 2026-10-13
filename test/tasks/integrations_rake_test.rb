require "test_helper"
require "rake"

class IntegrationsRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("integrations:recount_tool_definitions")
    Rake::Task["integrations:recount_tool_definitions"].reenable
  end

  test "recount_tool_definitions counts every connection's tools again, there and then" do
    integration = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
    tool = integration.tools.create!(name: "list_runs", description: "Lists the runs.", params_schema: { "type" => "object" })
    tool.update_columns(definition_chars: 1)

    output, = capture_io { Rake::Task["integrations:recount_tool_definitions"].invoke }

    assert_equal tool.definition_length, tool.reload.definition_chars
    assert_match "Counted", output
  end
end
