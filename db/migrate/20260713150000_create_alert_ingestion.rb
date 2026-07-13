class CreateAlertIngestion < ActiveRecord::Migration[8.1]
  def change
    create_table :alert_sources, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :workspace, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.string :provider, null: false
      t.string :endpoint_path, null: false
      t.string :secret_token, null: false
      t.jsonb :config, null: false, default: {}
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end
    add_index :alert_sources, :endpoint_path, unique: true
    add_index :alert_sources, [ :workspace_id, :name ], unique: true

    create_table :alert_groups, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :workspace, null: false, foreign_key: true, type: :uuid
      t.references :incident, null: false, foreign_key: true, type: :uuid
      t.string :content_signature, null: false
      t.datetime :window_expires_at, null: false
      t.timestamps
    end
    add_index :alert_groups, [ :workspace_id, :content_signature, :window_expires_at ],
              name: "index_alert_groups_on_signature_window"

    create_table :alerts, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :workspace, null: false, foreign_key: true, type: :uuid
      t.references :alert_source, null: false, foreign_key: true, type: :uuid
      t.string :external_id, null: false
      t.string :fingerprint, null: false
      t.string :status, null: false, default: "firing"
      t.jsonb :fields, null: false, default: {}
      t.jsonb :payload, null: false, default: {}
      t.integer :event_count, null: false, default: 1
      t.string :routing_state, null: false, default: "pending"
      t.datetime :received_at, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :resolved_at
      t.datetime :routed_at
      t.references :incident, foreign_key: true, type: :uuid
      t.references :alert_group, foreign_key: true, type: :uuid
      t.string :channel_message_id
      t.datetime :last_notified_at
      t.timestamps
    end
    add_index :alerts, [ :alert_source_id, :external_id ], unique: true
    add_index :alerts, [ :alert_source_id, :fingerprint, :status ]
    add_index :alerts, [ :workspace_id, :routing_state ]
  end
end
