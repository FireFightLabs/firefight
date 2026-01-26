class CreateIncidentRoles < ActiveRecord::Migration[8.1]
  def change
    create_table :incident_roles, id: :uuid do |t|
      t.uuid :workspace_id, null: false

      # Role identification
      t.string :name, null: false # "Incident Lead", "Commander", "Comms Lead"
      t.string :slug, null: false # "incident_lead", "commander", "comms_lead"
      t.text :description # Role responsibilities

      # Configuration
      t.integer :position, null: false, default: 0
      t.boolean :required, default: false # Must be filled before closing incident

      t.timestamps

      # Indexes
      t.index :workspace_id
      t.index [ :workspace_id, :slug ], unique: true
      t.index [ :workspace_id, :position ]
    end

    add_foreign_key :incident_roles, :workspaces
  end
end
