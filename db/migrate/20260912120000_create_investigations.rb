class CreateInvestigations < ActiveRecord::Migration[8.1]
  def change
    create_table :investigations, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.references :incident, type: :uuid, null: false, foreign_key: true
      t.references :agent, type: :uuid, foreign_key: true
      t.references :triggered_by, type: :uuid, polymorphic: true
      t.string :trigger_source, null: false
      t.string :status, null: false, default: "pending"
      t.integer :max_turns, null: false
      t.integer :max_tokens, null: false
      t.integer :turns_used, null: false, default: 0
      t.integer :tokens_used, null: false, default: 0
      t.decimal :confidence_threshold, precision: 3, scale: 2, null: false
      t.jsonb :seed_pack, null: false, default: {}
      t.jsonb :tool_set, null: false, default: []
      t.datetime :started_at
      t.datetime :completed_at
      t.string :error_summary
      t.timestamps
    end

    # One live run per incident, so a second request attaches instead of starting another.
    add_index :investigations, :incident_id, unique: true,
              where: "status IN ('pending', 'running')", name: "index_investigations_on_live_incident"
    add_index :investigations, [ :workspace_id, :created_at ]

    create_table :hypotheses, id: :uuid do |t|
      t.references :investigation, type: :uuid, null: false, foreign_key: true
      t.references :catalog_entry, type: :uuid, foreign_key: true
      t.text :assertion, null: false
      t.string :status, null: false, default: "open"
      t.string :specialist
      t.decimal :confidence, precision: 3, scale: 2
      t.integer :position, null: false
      t.integer :max_turns
      t.timestamps
    end
    add_index :hypotheses, [ :investigation_id, :position ], unique: true

    create_table :investigation_steps, id: :uuid do |t|
      t.references :investigation, type: :uuid, null: false, foreign_key: true
      t.references :hypothesis, type: :uuid, foreign_key: true
      t.integer :position, null: false
      t.string :action_key
      t.jsonb :params, null: false, default: {}
      # The ledger outlives the principals it names, so this is an id and not a foreign key.
      t.uuid :invocation_id
      t.text :compacted_result
      t.text :raw_result
      t.text :reasoning
      t.string :status, null: false, default: "pending"
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :investigation_steps, [ :investigation_id, :position ], unique: true

    create_table :findings, id: :uuid do |t|
      t.references :investigation, type: :uuid, null: false, foreign_key: true, index: { unique: true }
      t.references :winning_hypothesis, type: :uuid, foreign_key: { to_table: :hypotheses }
      t.references :outcome_by, type: :uuid, polymorphic: true
      t.text :summary
      t.string :remediation_type
      t.jsonb :proposed_solution, null: false, default: {}
      t.jsonb :evidence, null: false, default: []
      t.decimal :confidence, precision: 3, scale: 2
      t.jsonb :confidence_factors, null: false, default: {}
      t.string :published_state, null: false, default: "unpublished"
      t.datetime :published_at
      t.string :outcome
      t.datetime :outcome_at
      t.timestamps
    end
  end
end
