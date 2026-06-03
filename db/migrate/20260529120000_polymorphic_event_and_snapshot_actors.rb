class PolymorphicEventAndSnapshotActors < ActiveRecord::Migration[8.1]
  MEMBERSHIP = "WorkspaceMembership"

  def up
    # Recorder columns become polymorphic (WorkspaceMembership | ApiKey), so
    # their single-target FK to workspace_memberships can no longer hold.
    remove_foreign_key :incident_events, column: :user_id
    remove_foreign_key :incident_updates, column: :created_by_id
    remove_foreign_key :incident_action_updates, column: :actor_id
    remove_foreign_key :postmortem_updates, column: :edited_by_id

    # incident_events: user_id (WorkspaceMembership) -> polymorphic actor
    add_column :incident_events, :actor_type, :string
    rename_column :incident_events, :user_id, :actor_id
    execute "UPDATE incident_events SET actor_type = '#{MEMBERSHIP}' WHERE actor_id IS NOT NULL"
    add_index :incident_events, [ :actor_type, :actor_id ]

    # incident_updates.created_by (nullable recorder) -> polymorphic
    add_column :incident_updates, :created_by_type, :string
    execute "UPDATE incident_updates SET created_by_type = '#{MEMBERSHIP}' WHERE created_by_id IS NOT NULL"

    # incident_action_updates.actor (NOT NULL recorder) -> polymorphic
    add_column :incident_action_updates, :actor_type, :string
    execute "UPDATE incident_action_updates SET actor_type = '#{MEMBERSHIP}'"
    change_column_null :incident_action_updates, :actor_type, false

    # postmortem_updates.edited_by (NOT NULL recorder) -> polymorphic
    add_column :postmortem_updates, :edited_by_type, :string
    execute "UPDATE postmortem_updates SET edited_by_type = '#{MEMBERSHIP}'"
    change_column_null :postmortem_updates, :edited_by_type, false
  end

  def down
    remove_column :postmortem_updates, :edited_by_type
    remove_column :incident_action_updates, :actor_type
    remove_column :incident_updates, :created_by_type
    remove_index :incident_events, column: [ :actor_type, :actor_id ]
    rename_column :incident_events, :actor_id, :user_id
    remove_column :incident_events, :actor_type

    add_foreign_key :incident_events, :workspace_memberships, column: :user_id
    add_foreign_key :incident_updates, :workspace_memberships, column: :created_by_id
    add_foreign_key :incident_action_updates, :workspace_memberships, column: :actor_id
    add_foreign_key :postmortem_updates, :workspace_memberships, column: :edited_by_id
  end
end
