class CreateAbilityInvocations < ActiveRecord::Migration[8.1]
  def change
    create_table :ability_invocations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :workspace_id, null: false
      # Principal stored as values (type/id + label), with no FK. The ledger must
      # stay readable after the principal is deleted and portable to another
      # store.
      t.string :principal_type, null: false
      t.uuid :principal_id, null: false
      t.string :principal_label, null: false
      t.string :triggered_by_label
      t.string :action_key, null: false
      t.string :risk_level
      t.jsonb :scope, default: {}, null: false
      t.jsonb :params, default: {}, null: false
      t.string :decision, null: false
      t.string :idempotency_key, null: false
      t.uuid :incident_id
      t.string :outcome
      t.string :error_summary
      t.integer :duration_ms
      t.datetime :completed_at

      t.timestamps
    end

    add_index :ability_invocations, [ :workspace_id, :created_at ]
    add_index :ability_invocations, [ :principal_type, :principal_id, :created_at ],
              name: "index_ability_invocations_on_principal"
    add_index :ability_invocations, :action_key
    add_foreign_key :ability_invocations, :workspaces
  end
end
