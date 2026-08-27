class RemoveDefaultFromIncidentTypes < ActiveRecord::Migration[8.1]
  # Nothing ever read the default type. Incident creation leaves the type nil
  # when none is chosen, on Slack and on the API alike, and the declare modal
  # only preselects a type when editing an incident that already has one. A
  # workspace cannot know in advance whether the next incident is a security or
  # an infrastructure one, so the column was config that did nothing.
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
