class CreateWorkspaceAiAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :workspace_ai_accounts, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true, index: false
      t.string :kind, null: false, default: "api_key"
      t.string :provider, null: false
      t.string :label, null: false
      t.text :credentials
      t.string :credential_hint
      t.jsonb :settings, null: false, default: {}
      t.jsonb :models, null: false, default: {}
      t.integer :position, null: false
      t.boolean :enabled, null: false, default: true
      t.datetime :verified_at
      t.datetime :last_used_at
      t.datetime :out_of_credit_since
      t.datetime :failing_since
      t.string :last_error
      t.datetime :credentials_expire_at
      t.references :created_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.timestamps
      t.index [ :workspace_id, :position ], unique: true
    end
  end
end
