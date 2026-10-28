class AddSubscriptionsToWorkspaceAiAccounts < ActiveRecord::Migration[8.1]
  def change
    # The name the subscription proxy gives the sign-in. One sign-in belongs to one account in one workspace.
    add_column :workspace_ai_accounts, :proxy_credential, :string
    # What the proxy last said of it: its models, its limit and whether its sign-in still works. Never a token.
    add_column :workspace_ai_accounts, :proxy_state, :jsonb, default: {}, null: false
    add_index :workspace_ai_accounts, :proxy_credential, unique: true, where: "proxy_credential IS NOT NULL"

    # A sign-in a person started at the proxy and has not finished. The state names it at the proxy, and nothing here
    # is a token.
    create_table :subscription_sign_ins, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :started_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      # Set when it signs an existing account in again.
      t.references :workspace_ai_account, type: :uuid, foreign_key: { on_delete: :cascade }
      t.string :subscription, null: false
      t.string :proxy, null: false
      t.string :state, null: false
      t.string :url, null: false
      t.string :user_code
      t.datetime :expires_at
      t.string :status, null: false, default: "waiting"
      t.string :error
      t.timestamps
    end
    add_index :subscription_sign_ins, :state, unique: true
    add_index :subscription_sign_ins, [ :proxy, :status ]
  end
end
