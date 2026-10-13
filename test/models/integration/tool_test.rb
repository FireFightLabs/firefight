require "test_helper"

class Integration::ToolTest < ActiveSupport::TestCase
  setup do
    @integration = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
  end

  test "a tool keeps how long its definition is, as the held tools budget counts it, and counts again when it changes" do
    schema = { "type" => "object", "properties" => { "repo" => { "type" => "string" } } }
    tool = @integration.tools.create!(name: "list_runs", description: "Lists the runs.", params_schema: schema)
    assert_equal "list_runs".size + "Lists the runs.".size + tool.offered_schema.to_json.size, tool.reload.definition_chars

    tool.update!(description: "Lists the workflow runs of a repository.")
    assert_equal "list_runs".size + "Lists the workflow runs of a repository.".size + tool.offered_schema.to_json.size, tool.reload.definition_chars

    tool.update!(params_schema: { "type" => "object" })
    assert_equal "list_runs".size + "Lists the workflow runs of a repository.".size + tool.offered_schema.to_json.size, tool.reload.definition_chars

    tool.update!(name: "list_workflow_runs", description: nil)
    assert_equal "list_workflow_runs".size + tool.offered_schema.to_json.size, tool.reload.definition_chars
  end

  test "the length counts the schema the model is handed, with the connection's environment argument, not the tool's own" do
    @integration.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id)
    @integration.integration_environments.create!(catalog_entry_id: catalog_entries(:development_env).id)
    schema = { "type" => "object", "properties" => { "repo" => { "type" => "string" } } }

    tool = @integration.tools.create!(name: "list_runs", description: "Lists the runs.", params_schema: schema)

    offered = tool.offered_schema
    assert_equal %w[production development], offered.dig("properties", Integration::Tool::ENVIRONMENT_ARG, "enum")
    assert_equal "list_runs".size + "Lists the runs.".size + offered.to_json.size, tool.reload.definition_chars
    assert_operator tool.definition_chars, :>, "list_runs".size + "Lists the runs.".size + schema.to_json.size
  end

  test "switching a tool on or off leaves its length as it was" do
    tool = @integration.tools.create!(name: "list_runs", description: "Lists the runs.", params_schema: { "type" => "object" })
    tool.update_columns(definition_chars: 7)

    tool.update!(enabled: true)
    assert_equal 7, tool.reload.definition_chars
  end
end
