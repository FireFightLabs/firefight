class CreateIncidentActionUpdates < ActiveRecord::Migration[8.1]
  def change
    create_table :incident_action_updates, id: :uuid do |t|
      t.references :incident_action, type: :uuid, null: false, foreign_key: true
      t.string :action_update_type, null: false
      t.string :action_type, null: false
      t.references :actor, type: :uuid, null: false, foreign_key: { to_table: :workspace_memberships }

      t.timestamps
    end

    add_index :incident_action_updates, [ :incident_action_id, :created_at ]
    add_index :incident_action_updates, :action_update_type
  end
end
