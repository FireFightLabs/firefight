class CreateIncidentActions < ActiveRecord::Migration[8.1]
  def change
    create_table :incident_actions, id: :uuid do |t|
      t.uuid :incident_id, null: false
      t.uuid :created_by_id, null: false
      t.uuid :assignee_id

      t.string :action_type, null: false, default: "action" # "action" or "followup"
      t.text :description, null: false
      t.string :status, default: "open" # "open", "in_progress", "done"

      t.string :slack_message_ts
      t.jsonb :platform_data, default: {}

      t.timestamps
      t.datetime :deleted_at

      # indexes
      t.index :deleted_at
      t.index [ :incident_id, :action_type ]
      t.index [ :incident_id, :status ]
      t.index :assignee_id
    end

    # foreign key constraints
    add_foreign_key :incident_actions, :incidents
    add_foreign_key :incident_actions, :workspace_memberships, column: :created_by_id
    add_foreign_key :incident_actions, :workspace_memberships, column: :assignee_id
  end
end
