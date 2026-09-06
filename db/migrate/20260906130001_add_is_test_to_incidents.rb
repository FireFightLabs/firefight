# Test incidents behave like real ones and are not counted in metrics.
class AddIsTestToIncidents < ActiveRecord::Migration[8.1]
  def change
    add_column :incidents, :is_test, :boolean, default: false, null: false
    add_index :incidents, :workspace_id, where: "is_test", name: "index_incidents_on_workspace_id_where_test"
  end
end
