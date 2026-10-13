require "test_helper"

class Integration::ToolTest < ActiveSupport::TestCase
  setup do
    @integration = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
  end

  test "a tool keeps how long its definition is, as the held tools budget counts it, and counts again when it changes" do
    schema = { "type" => "object", "properties" => { "repo" => { "type" => "string" } } }
    tool = @integration.tools.create!(name: "list_runs", description: "Lists the runs.", params_schema: schema)
    assert_equal "list_runs".size + "Lists the runs.".size + schema.to_json.size, tool.reload.definition_chars

    tool.update!(description: "Lists the workflow runs of a repository.")
    assert_equal "list_runs".size + "Lists the workflow runs of a repository.".size + schema.to_json.size, tool.reload.definition_chars

    tool.update!(params_schema: { "type" => "object" })
    assert_equal "list_runs".size + "Lists the workflow runs of a repository.".size + { "type" => "object" }.to_json.size, tool.reload.definition_chars

    tool.update!(name: "list_workflow_runs", description: nil)
    assert_equal "list_workflow_runs".size + { "type" => "object" }.to_json.size, tool.reload.definition_chars
  end

  test "switching a tool on or off leaves its length as it was" do
    tool = @integration.tools.create!(name: "list_runs", description: "Lists the runs.", params_schema: { "type" => "object" })
    tool.update_columns(definition_chars: 7)

    tool.update!(enabled: true)
    assert_equal 7, tool.reload.definition_chars
  end

  test "the name the agent calls a tool by is its connection's slug and its own name, with no dot" do
    tool = @integration.tools.create!(name: "actions.list_runs")

    assert_equal "github_actions_list_runs", tool.model_facing_name
    assert_equal tool.model_facing_name, Integration::Tool.model_facing_name("github", "actions.list_runs")
  end
end
