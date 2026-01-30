class CreateIncidentEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :incident_events, id: :uuid do |t|
      t.uuid :incident_id, null: false
      t.uuid :user_id # Optional: system events have no user
      t.string :event_type, null: false

      # Full snapshots with denormalized data
      # Structure: { schema_version: 1, before: {...}, after: {...}, changed_fields: [...], details: "..." }
      t.jsonb :metadata, default: {}

      t.datetime :created_at, null: false

      # Indexes
      t.index :incident_id
      t.index [ :incident_id, :created_at ]
      t.index :event_type
      t.index :user_id
      t.index :metadata, using: :gin # For JSONB queries
    end

    # Foreign key constraints
    add_foreign_key :incident_events, :incidents
    add_foreign_key :incident_events, :workspace_memberships, column: :user_id
  end
end
