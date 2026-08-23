class HardenAlertIngestion < ActiveRecord::Migration[8.1]
  def up
    # Collapse any pre-existing duplicate open alerts (keep the freshest) so
    # the partial unique index below can be created.
    execute <<~SQL
      UPDATE alerts SET status = 'resolved', resolved_at = NOW()
      WHERE id IN (
        SELECT id FROM (
          SELECT id, ROW_NUMBER() OVER (PARTITION BY alert_source_id, fingerprint ORDER BY last_seen_at DESC) AS rn
          FROM alerts WHERE status = 'firing'
        ) ranked WHERE rn > 1
      )
    SQL

    # The DB backstop for fingerprint dedup, at most one open alert per
    # (source, fingerprint). Concurrent inserts lose with RecordNotUnique and
    # fold into the record_firing! path.
    add_index :alerts, [ :alert_source_id, :fingerprint ], unique: true,
              where: "status = 'firing'", name: "index_alerts_on_open_fingerprint"

    # The sweep job's exact shape. Stays near-empty.
    add_index :alerts, :received_at, where: "routing_state = 'pending'",
              name: "index_alerts_on_pending_received_at"

    # The recent-alerts page, workspace-scoped, newest first.
    add_index :alerts, [ :workspace_id, :last_seen_at ]

    add_column :alerts, :routing_attempts, :integer, default: 0, null: false

    add_column :alert_sources, :last_received_at, :datetime
    add_column :alert_sources, :last_rejected_at, :datetime
    add_column :alert_sources, :last_rejection_reason, :string
  end

  def down
    remove_column :alert_sources, :last_rejection_reason
    remove_column :alert_sources, :last_rejected_at
    remove_column :alert_sources, :last_received_at
    remove_column :alerts, :routing_attempts
    remove_index :alerts, [ :workspace_id, :last_seen_at ]
    remove_index :alerts, name: "index_alerts_on_pending_received_at"
    remove_index :alerts, name: "index_alerts_on_open_fingerprint"
  end
end
