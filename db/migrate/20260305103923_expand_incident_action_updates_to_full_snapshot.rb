class ExpandIncidentActionUpdatesToFullSnapshot < ActiveRecord::Migration[8.1]
  def change
    rename_column :incident_action_updates, :action_update_type, :update_type

    add_reference :incident_action_updates, :incident, type: :uuid, null: false, foreign_key: true
    add_reference :incident_action_updates, :created_by, type: :uuid, null: false,
                  foreign_key: { to_table: :workspace_memberships }
    add_reference :incident_action_updates, :assignee, type: :uuid, null: true,
                  foreign_key: { to_table: :workspace_memberships }
    add_column :incident_action_updates, :description, :text, null: false
    add_column :incident_action_updates, :status, :string, null: false
    add_column :incident_action_updates, :message_ts, :string
    add_column :incident_action_updates, :platform_data, :jsonb, default: {}, null: false
    add_column :incident_action_updates, :deleted_at, :datetime

    add_column :incident_action_updates, :changed_fields, :jsonb, default: [], null: false
  end
end
