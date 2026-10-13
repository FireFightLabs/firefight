# How long a tool's definition is, its name, description and schema as FirefightAi.fits_up_front? counts them, kept on
# the row so whether a workspace's tools fit the held tools budget is one sum rather than loading every schema.
class AddDefinitionCharsToIntegrationTools < ActiveRecord::Migration[8.1]
  class Tool < ActiveRecord::Base
    self.table_name = "integration_tools"
  end

  def up
    add_column :integration_tools, :definition_chars, :bigint, null: false, default: 0
    Tool.reset_column_information

    Tool.select(:id, :name, :description, :params_schema).find_each do |tool|
      tool.update_columns(definition_chars: tool.name.to_s.size + tool.description.to_s.size + tool.params_schema.to_json.size)
    end
  end

  def down
    remove_column :integration_tools, :definition_chars
  end
end
