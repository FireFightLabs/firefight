require "test_helper"
require Rails.root.join("db/migrate/20261013120000_add_definition_chars_to_integration_tools")

class AddDefinitionCharsToIntegrationToolsTest < ActiveSupport::TestCase
  teardown { Integration::Tool.reset_column_information }

  test "every tool from before the column is given how long its offered definition is, as the held tools budget counts it" do
    integration = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
    schema = { "type" => "object", "properties" => { "repo" => { "type" => "string", "description" => "owner/name" } }, "required" => [ "repo" ] }
    described = integration.tools.create!(name: "list_runs", description: "Lists the runs.", params_schema: schema)
    bare = integration.tools.create!(name: "whoami")
    integration.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id)
    integration.integration_environments.create!(catalog_entry_id: catalog_entries(:development_env).id)

    migrate(:down)
    migrate(:up)
    Integration::Tool.reset_column_information

    described.reload
    bare.reload
    assert_equal %w[production development], described.offered_schema.dig("properties", Integration::Tool::ENVIRONMENT_ARG, "enum")
    assert_equal "list_runs".size + "Lists the runs.".size + described.offered_schema.to_json.size, described.definition_chars
    assert_equal "whoami".size + bare.offered_schema.to_json.size, bare.definition_chars
  end

  private

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { AddDefinitionCharsToIntegrationTools.new.migrate(direction) }
  end
end
