require "test_helper"

class Integration::ToolTest < ActiveSupport::TestCase
  setup do
    @integration = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
  end

  test "a tool keeps how long its definition is as a model is handed it, and counts again when it changes" do
    schema = { "type" => "object", "properties" => { "repo" => { "type" => "string" } } }
    tool = @integration.tools.create!(name: "list_runs", description: "Lists the runs.", params_schema: schema)
    assert_equal "github_list_runs".size + "Lists the runs.".size + tool.offered_schema.to_json.size, tool.reload.definition_chars

    tool.update!(description: "Lists the workflow runs of a repository.")
    assert_equal "github_list_runs".size + "Lists the workflow runs of a repository.".size + tool.offered_schema.to_json.size, tool.reload.definition_chars

    tool.update!(params_schema: { "type" => "object" })
    assert_equal "github_list_runs".size + "Lists the workflow runs of a repository.".size + tool.offered_schema.to_json.size, tool.reload.definition_chars

    tool.update!(name: "list_workflow_runs", description: nil)
    assert_equal "github_list_workflow_runs".size + tool.offered_schema.to_json.size, tool.reload.definition_chars
  end

  test "the length counts the name with the connection's slug and the schema with the connection's environment argument" do
    @integration.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id)
    @integration.integration_environments.create!(catalog_entry_id: catalog_entries(:development_env).id)
    schema = { "type" => "object", "properties" => { "repo" => { "type" => "string" } } }

    tool = @integration.tools.create!(name: "list_runs", description: "Lists the runs.", params_schema: schema)

    offered = tool.offered_schema
    assert_equal %w[production development], offered.dig("properties", Integration::Tool::ENVIRONMENT_ARG, "enum")
    assert_equal tool.model_facing_name.size + "Lists the runs.".size + offered.to_json.size, tool.reload.definition_chars
    assert_operator tool.definition_chars, :>, "list_runs".size + "Lists the runs.".size + schema.to_json.size
  end

  test "the length counts what an agent reads beside the tool, such as what its connection's installation lacks" do
    row = @integration.integration_environments.create!
    row.store_installation!("42")
    row.installation_checked!(Integrations::Installations::Installation.new(account: "acme", page: "https://github.com/settings/installations/42",
                                                                             access: { "contents" => "read", "metadata" => "read" }))

    tool = @integration.tools.create!(name: "workflow_runs", read_only: true, description: "Lists runs.")

    assert_equal "Needs Actions read in the GitHub App. Lists runs.", tool.described_for_agents
    assert_equal tool.model_facing_name.size + tool.described_for_agents.size + tool.offered_schema.to_json.size, tool.reload.definition_chars
  end

  test "an agent description longer than an agent is handed counts only as much as it is handed" do
    assert_equal Chat::Tools::FULL_DESCRIPTION, Integration::Tool::AGENT_DESCRIPTION_LIMIT

    tool = @integration.tools.create!(name: "list_runs", description: "word " * 1_000, params_schema: { "type" => "object" })

    assert_equal tool.model_facing_name.size + Integration::Tool::AGENT_DESCRIPTION_LIMIT + tool.offered_schema.to_json.size, tool.reload.definition_chars
  end

  test "switching a tool on or off leaves its length as it was" do
    tool = @integration.tools.create!(name: "list_runs", description: "Lists the runs.", params_schema: { "type" => "object" })
    tool.update_columns(definition_chars: 7)

    tool.update!(enabled: true)
    assert_equal 7, tool.reload.definition_chars
  end

  test "the length is counted again when the connection's environments change what the tool is offered with" do
    tool = @integration.tools.create!(name: "list_runs", description: "Lists the runs.", params_schema: { "type" => "object" })
    offered_length = -> { tool.reload.definition_length }
    alone = offered_length.call

    production = @integration.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id)
    @integration.integration_environments.create!(catalog_entry_id: catalog_entries(:development_env).id)
    assert_operator offered_length.call, :>, alone
    assert_equal offered_length.call, tool.reload.definition_chars

    production.update!(enabled: false)
    assert_equal offered_length.call, tool.reload.definition_chars

    production.destroy!
    assert_equal offered_length.call, tool.reload.definition_chars
  end

  test "the length is counted again when the connection reaches several scopes and so offers a scope argument" do
    integration = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_NATIVE, provider: "vercel", name: "Sites", slug: "sites")
    row = integration.integration_environments.create!
    tool = integration.tools.create!(name: "list_deployments", description: "Lists deployments.", params_schema: { "type" => "object" })
    one_scope = tool.reload.definition_chars

    row.store_fields!(Integrations::Packs::Vercel::TEAM => %w[team_a team_b])
    assert_includes tool.reload.offered_schema["properties"].keys, Integrations::Packs::Vercel::TEAM
    assert_operator tool.definition_chars, :>, one_scope
    assert_equal tool.definition_length, tool.definition_chars
  end
end
