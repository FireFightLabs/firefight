class CreateIncidentUpdates < ActiveRecord::Migration[8.1]
  def change
    create_table :incident_updates, id: :uuid do |t|
      t.references :incident, type: :uuid, null: false, foreign_key: true

      # State snapshot (mirrors incidents table)
      t.uuid :workspace_id, null: false
      t.references :declared_by, type: :uuid, null: false, foreign_key: { to_table: :workspace_memberships }
      t.references :incident_status, type: :uuid, null: false, foreign_key: true
      t.references :incident_severity, type: :uuid, null: false, foreign_key: true
      t.references :lead, type: :uuid, null: true, foreign_key: { to_table: :workspace_memberships }
      t.integer :sequence_number, null: false
      t.string :identifier, null: false
      t.string :name
      t.text :summary
      t.boolean :is_private, default: false, null: false
      t.string :channel_id
      t.string :channel_name
      t.string :initial_message_ts
      t.string :announcement_message_ts
      t.jsonb :platform_data, default: {}, null: false
      t.jsonb :custom_fields, default: {}, null: false
      t.datetime :declared_at, null: false
      t.datetime :resolved_at
      t.datetime :channel_archived_at
      t.string :channel_archived_by
      t.datetime :next_update_at
      t.datetime :deleted_at

      # Update-specific fields
      t.string :update_type, null: false
      t.references :created_by, type: :uuid, null: true, foreign_key: { to_table: :workspace_memberships }
      t.text :message
      t.jsonb :changed_fields, default: [], null: false

      t.timestamps
    end

    add_index :incident_updates, [ :incident_id, :created_at ]
    add_index :incident_updates, :update_type
    add_foreign_key :incident_updates, :workspaces
  end
end
