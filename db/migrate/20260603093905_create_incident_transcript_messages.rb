class CreateIncidentTranscriptMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :incident_transcript_messages, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.references :incident, type: :uuid, null: false, foreign_key: true

      t.string :slack_ts, null: false
      t.string :slack_thread_ts
      t.string :slack_user_id, null: false
      t.references :workspace_membership, type: :uuid, foreign_key: true

      t.text :content, null: false
      t.datetime :posted_at, null: false
      t.boolean :scrubbed, null: false, default: false
      t.datetime :deleted_at

      t.timestamps

      # Idempotent ingest: Slack Events retries cannot dup
      t.index [ :workspace_id, :incident_id, :slack_ts ], unique: true, name: "index_transcript_messages_on_workspace_incident_slack_ts"

      # Summary generator reads messages chronologically per incident
      t.index [ :incident_id, :posted_at ]

      # Retention purge + uninstall queries scan by workspace and age
      t.index [ :workspace_id, :created_at ]

      # Admin redact-by-user lookups
      t.index [ :workspace_id, :slack_user_id ]
    end
  end
end
