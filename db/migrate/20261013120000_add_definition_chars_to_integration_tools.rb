# How long a tool's definition is, as FirefightAi.fits_up_front? counts what a model is handed, kept on the row so
# whether a workspace's tools fit the held tools budget is one sum rather than loading every schema.
# The backfill is plain SQL, so it never changes with the app's code: the name a model calls the tool by (the
# connection's slug and the tool's name joined with an underscore, dots turned to underscores), its description and its
# own schema. The environment and scope arguments the app adds are written by
# bin/rails integrations:recount_tool_definitions, run once after this.
# The column has no default and must be above zero, so a row written without the count fails rather than reading as 0.
class AddDefinitionCharsToIntegrationTools < ActiveRecord::Migration[8.1]
  def up
    add_column :integration_tools, :definition_chars, :bigint
    execute <<~SQL.squish
      UPDATE integration_tools
      SET definition_chars = length(replace(integrations.slug || '_' || integration_tools.name, '.', '_'))
        + length(coalesce(integration_tools.description, ''))
        + length(CASE WHEN integration_tools.params_schema = '{}'::jsonb THEN '{"type":"object"}' ELSE integration_tools.params_schema::text END)
      FROM integrations
      WHERE integrations.id = integration_tools.integration_id
    SQL
    change_column_null :integration_tools, :definition_chars, false
    add_check_constraint :integration_tools, "definition_chars > 0", name: "integration_tools_definition_chars_counted"
  end

  def down
    remove_column :integration_tools, :definition_chars
  end
end
