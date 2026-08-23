class CreateIncidentSummaries < ActiveRecord::Migration[8.1]
  def change
    create_table :incident_summaries, id: :uuid do |t|
      # One summary per incident. Upsert into this row
      t.references :incident, type: :uuid, null: false, foreign_key: true, index: { unique: true }
      t.references :workspace, type: :uuid, null: false, foreign_key: true

      # Links to the Inference row that produced this summary (cost attribution)
      t.references :inference, type: :uuid, foreign_key: true

      t.text :content, null: false
      t.string :summary_up_to_ts, null: false
      t.datetime :generated_at, null: false
      t.string :model, null: false

      t.timestamps

      # Retention purge + uninstall scan by workspace
      t.index [ :workspace_id, :generated_at ]
    end
  end
end
