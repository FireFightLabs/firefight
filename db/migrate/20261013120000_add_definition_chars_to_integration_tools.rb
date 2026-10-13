# How long a tool's definition is, its name, description and offered schema as FirefightAi.fits_up_front? counts them,
# kept on the row so whether a workspace's tools fit the held tools budget is one sum rather than loading every schema.
# The offered schema adds the environment and scope arguments from the tool's connection, so the backfill counts it
# through the model (Integration::Tool#definition_length).
class AddDefinitionCharsToIntegrationTools < ActiveRecord::Migration[8.1]
  def up
    add_column :integration_tools, :definition_chars, :bigint, null: false, default: 0
    Integration::Tool.reset_column_information

    Integration::Tool.includes(:integration).find_each do |tool|
      tool.update_columns(definition_chars: tool.definition_length)
    end
  end

  def down
    remove_column :integration_tools, :definition_chars
  end
end
