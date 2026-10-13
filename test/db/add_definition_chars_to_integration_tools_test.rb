require "test_helper"
require Rails.root.join("db/migrate/20261013120000_add_definition_chars_to_integration_tools")

class AddDefinitionCharsToIntegrationToolsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  teardown { Integration::Tool.reset_column_information }

  test "every tool from before the column is given how long its name, cleaned description and own schema are, counted in SQL" do
    integration = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
    schema = { "type" => "object", "properties" => { "repo" => { "type" => "string", "description" => "owner/name" } }, "required" => [ "repo" ] }
    described = integration.tools.create!(name: "list_runs", description: " Lists  the\nruns. ", params_schema: schema)
    bare = integration.tools.create!(name: "whoami")
    long = integration.tools.create!(name: "search", description: "x" * (Integration::Tool::AGENT_DESCRIPTION_LIMIT + 50))

    migrate(:down)
    Integration::Tool.reset_column_information
    assert_enqueued_jobs 1, only: Integrations::ToolDefinitionRecountJob do
      migrate(:up)
    end
    Integration::Tool.reset_column_information

    stored_schema = Integration::Tool.where(id: described.id).pick(Arel.sql("params_schema::text AS schema_text"))
    assert_equal "github_list_runs".size + "Lists the runs.".size + stored_schema.size, described.reload.definition_chars
    assert_equal "github_whoami".size + '{"type": "object"}'.size, bare.reload.definition_chars
    assert_equal "github_search".size + Integration::Tool::AGENT_DESCRIPTION_LIMIT + '{"type": "object"}'.size, long.reload.definition_chars
  end

  test "a tool written with a zero length, or with none, is refused rather than counted as nothing" do
    integration = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
    tool = integration.tools.create!(name: "list_runs", description: "Lists the runs.")
    assert_operator tool.reload.definition_chars, :>, 0

    assert_raises(ActiveRecord::CheckViolation) do
      Integration::Tool.transaction(requires_new: true) { tool.update_columns(definition_chars: 0) }
    end
    assert_raises(ActiveRecord::NotNullViolation) do
      Integration::Tool.transaction(requires_new: true) { Integration::Tool.insert_all([ { integration_id: integration.id, name: "whoami" } ]) }
    end
    assert_operator tool.reload.definition_chars, :>, 0
  end

  test "the exact count is enqueued by the job's name, so a job renamed or gone later leaves the migration running" do
    assert_equal Integrations::ToolDefinitionRecountJob.name, AddDefinitionCharsToIntegrationTools::RECOUNT_JOB

    assert_no_enqueued_jobs do
      AddDefinitionCharsToIntegrationTools.new.send(:enqueue_recount, "Integrations::NoSuchJob")
    end
  end

  private

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { AddDefinitionCharsToIntegrationTools.new.migrate(direction) }
  end
end
