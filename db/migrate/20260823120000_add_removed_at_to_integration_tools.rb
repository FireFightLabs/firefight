class AddRemovedAtToIntegrationTools < ActiveRecord::Migration[8.1]
  def change
    add_column :integration_tools, :removed_at, :datetime
  end
end
