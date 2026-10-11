class AddMarkedReadToIntegrationTools < ActiveRecord::Migration[8.1]
  def change
    add_column :integration_tools, :marked_read, :boolean, default: false, null: false
  end
end
