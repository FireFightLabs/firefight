class CreateInvestigationChecksAndNotices < ActiveRecord::Migration[8.1]
  def change
    create_table :investigation_checks, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false
      t.text :notes
      t.string :cadence, null: false
      t.integer :hour, null: false
      t.integer :weekday
      t.string :time_zone, null: false
      t.datetime :next_run_at, null: false
      t.datetime :last_run_at
      t.datetime :deleted_at
      t.references :created_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.timestamps
    end
    add_index :investigation_checks, "workspace_id, lower(name)", unique: true, name: "index_investigation_checks_on_workspace_and_name"
    add_index :investigation_checks, :next_run_at, where: "deleted_at IS NULL", name: "index_investigation_checks_due"

    create_table :investigation_notices, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.references :check, type: :uuid, foreign_key: { to_table: :investigation_checks, on_delete: :nullify }
      t.references :investigation, type: :uuid, foreign_key: { on_delete: :nullify }
      t.references :resource, type: :uuid, foreign_key: { to_table: :resource_map_resources, on_delete: :nullify }
      t.string :key, null: false
      t.string :signal, null: false
      t.string :topic, null: false
      t.text :summary, null: false
      t.string :severity, null: false
      t.date :due_on
      t.string :channel_id
      t.string :message_id
      t.integer :times_said, null: false, default: 0
      t.boolean :unsaid, null: false, default: false
      t.string :unsaid_reason
      t.datetime :first_said_at
      t.datetime :last_said_at
      t.datetime :last_seen_at, null: false
      t.timestamps
    end
    add_index :investigation_notices, [ :workspace_id, :key ], unique: true
    add_index :investigation_notices, [ :workspace_id, :last_seen_at ]

    add_column :workspaces, :halon_monitoring_channel, :string
    add_column :workspaces, :halon_security_events_enabled, :boolean, null: false, default: true
  end
end
