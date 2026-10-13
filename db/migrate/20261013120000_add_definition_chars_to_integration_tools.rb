# How long a tool's definition is, its name, description and offered schema as FirefightAi.fits_up_front? counts them,
# kept on the row so whether a workspace's tools fit the held tools budget is one sum rather than loading every schema.
# The app counts it on every save (Integration::Tool#definition_length). The backfill is plain SQL so this migration
# never depends on the model: the model-facing name, the description cleaned and capped as Chat::Tools.clean does, and
# the tool's own schema. What the connection adds when a tool is offered (the environment and scope arguments, a
# replica's wording, a missing permission note) comes from its settings, which SQL cannot read, so it is counted the
# next time the tool or its connection's environments change. There is no default, and the check refuses a zero, so a
# row written without the count fails rather than counting as nothing.
class AddDefinitionCharsToIntegrationTools < ActiveRecord::Migration[8.1]
  def up
    add_column :integration_tools, :definition_chars, :bigint

    execute <<~SQL.squish
      UPDATE integration_tools
      SET definition_chars =
        length(replace(integrations.slug || '_' || integration_tools.name, '.', '_'))
        + least(length(btrim(regexp_replace(coalesce(integration_tools.description, ''), '[[:space:][:cntrl:]]+', ' ', 'g'))), 2000)
        + length(coalesce(nullif(integration_tools.params_schema, '{}'::jsonb), '{"type":"object"}'::jsonb)::text)
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
