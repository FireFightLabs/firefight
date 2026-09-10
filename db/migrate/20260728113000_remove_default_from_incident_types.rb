class RemoveDefaultFromIncidentTypes < ActiveRecord::Migration[8.1]
  # Nothing ever read the default type. Incident creation leaves the type nil when none is chosen.
  def up
    remove_index :incident_types, column: :workspace_id,
      name: "index_incident_types_on_single_default_per_workspace"
    remove_column :incident_types, :is_default
  end

  def down
    add_column :incident_types, :is_default, :boolean, default: false
    add_index :incident_types, :workspace_id, unique: true, where: "is_default",
      name: "index_incident_types_on_single_default_per_workspace"
  end
end
