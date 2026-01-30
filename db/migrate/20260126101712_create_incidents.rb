class CreateIncidents < ActiveRecord::Migration[8.1]
  def change
    create_table :incidents, id: :uuid do |t|
      # Workspace and user references
      t.uuid :workspace_id, null: false
      t.uuid :declared_by_id, null: false # Who declared the incident

      # Configurable references (NOT hardcoded strings)
      t.uuid :incident_status_id, null: false
      t.uuid :incident_severity_id, null: false

      # Sequential numbering (workspace-scoped)
      t.integer :sequence_number, null: false
      t.string :identifier, null: false # "INC-001", "INC-002"

      # Core fields (MUTABLE - edited in place)
      t.string :name
      t.text :summary
      t.boolean :is_private, default: false

      # Slack/Teams integration fields
      t.string :slack_channel_id
      t.string :slack_channel_name
      t.string :initial_message_ts # Pinned quick actions message
      t.string :announcement_message_ts # Message in #incidents channel

      # Platform-agnostic metadata (Slack timestamps, Teams IDs, etc.)
      t.jsonb :platform_data, default: {}

      # Custom fields (future feature)
      t.jsonb :custom_fields, default: {}

      # Lifecycle timestamps
      t.datetime :declared_at, null: false
      t.datetime :resolved_at # Set when moved to "closed" category status

      t.timestamps
      t.datetime :deleted_at

      # Indexes for performance
      t.index [ :workspace_id, :deleted_at ]
      t.index :workspace_id
      t.index [ :workspace_id, :sequence_number ], unique: true
      t.index [ :workspace_id, :identifier ], unique: true
      t.index [ :workspace_id, :incident_status_id ]
      t.index :incident_status_id
      t.index :incident_severity_id
      t.index :declared_at
      t.index :declared_by_id
    end

    # Foreign key constraints
    add_foreign_key :incidents, :workspaces
    add_foreign_key :incidents, :workspace_memberships, column: :declared_by_id
    add_foreign_key :incidents, :incident_statuses
    add_foreign_key :incidents, :incident_severities
  end
end
