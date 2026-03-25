class CreateApiKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :api_keys, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.references :created_by, type: :uuid, null: false, foreign_key: { to_table: :workspace_memberships }
      t.string :name, null: false
      t.string :token_digest, null: false
      t.string :token_prefix, null: false, limit: 12
      t.jsonb :permissions, null: false, default: {}
      t.boolean :active, null: false, default: true
      t.datetime :expires_at
      t.datetime :last_used_at
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :api_keys, :token_digest, unique: true
    add_index :api_keys, [ :workspace_id, :deleted_at ]
  end
end
