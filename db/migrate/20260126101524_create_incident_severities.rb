class CreateIncidentSeverities < ActiveRecord::Migration[8.1]
  def change
    create_table :incident_severities, id: :uuid do |t|
      t.uuid :workspace_id, null: false

      t.string :name, null: false # "SEV1", "Critical", "P0", etc.
      t.string :slug, null: false # "sev1", "critical", "p0"
      t.text :description

      # Severity ranking (higher = more severe)
      t.integer :rank, null: false # 1=lowest severity, 5=highest severity

      # Ordering and defaults
      t.integer :position, null: false, default: 0 # For UI ordering
      t.boolean :is_default, default: false # Default severity for new incidents

      # UI configuration
      t.string :color # Hex color code like "#DC143C"

      t.timestamps

      t.index :workspace_id
      t.index [ :workspace_id, :slug ], unique: true
      t.index [ :workspace_id, :position ]
      t.index [ :workspace_id, :rank ]
      t.index [ :workspace_id, :is_default ]
    end

    add_foreign_key :incident_severities, :workspaces
  end
end
