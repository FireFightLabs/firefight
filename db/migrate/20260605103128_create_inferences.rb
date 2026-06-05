class CreateInferences < ActiveRecord::Migration[8.1]
  def change
    create_table :inferences, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.references :member, type: :uuid, foreign_key: { to_table: :workspace_memberships }
      t.references :api_key, type: :uuid, foreign_key: true
      t.references :inferable, type: :uuid, polymorphic: true

      t.string :feature, null: false
      t.string :provider, null: false
      t.string :model, null: false

      t.integer :input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0
      t.integer :cache_read_tokens, null: false, default: 0
      t.integer :cache_write_tokens, null: false, default: 0
      t.integer :cost_cents, null: false, default: 0
      t.integer :latency_ms, null: false, default: 0

      t.string :stop_reason
      t.string :provider_request_id
      t.string :status, null: false
      t.string :error_class

      t.datetime :created_at, null: false

      # Time-series queries (daily/weekly trends per workspace)
      t.index [ :workspace_id, :created_at ]

      # Cost-per-feature aggregations
      t.index [ :workspace_id, :feature, :created_at ]

      # Per-incident (or per-postmortem, etc.) cost lookups via the polymorphic anchor
      t.index [ :workspace_id, :inferable_type, :inferable_id ]
    end
  end
end
