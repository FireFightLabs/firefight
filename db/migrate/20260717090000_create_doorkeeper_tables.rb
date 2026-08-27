class CreateDoorkeeperTables < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_applications, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :name, null: false
      t.string :uid, null: false
      # Public clients (MCP dynamic registration) have no secret.
      t.string :secret, null: true
      t.text :redirect_uri, null: false
      t.string :scopes, null: false, default: ""
      t.boolean :confidential, null: false, default: false
      t.timestamps null: false
    end
    add_index :oauth_applications, :uid, unique: true

    create_table :oauth_access_grants, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :resource_owner_id, null: false
      t.references :application, type: :uuid, null: false, foreign_key: { to_table: :oauth_applications }
      t.string :token, null: false
      t.integer :expires_in, null: false
      t.text :redirect_uri, null: false
      t.string :scopes, null: false, default: ""
      t.datetime :created_at, null: false
      t.datetime :revoked_at
      t.string :code_challenge
      t.string :code_challenge_method
    end
    add_index :oauth_access_grants, :token, unique: true
    add_foreign_key :oauth_access_grants, :workspace_memberships, column: :resource_owner_id

    create_table :oauth_access_tokens, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :resource_owner_id, null: false
      t.references :application, type: :uuid, null: false, foreign_key: { to_table: :oauth_applications }
      t.string :token, null: false
      t.string :refresh_token
      t.integer :expires_in
      t.string :scopes
      t.datetime :created_at, null: false
      t.datetime :revoked_at
      t.string :previous_refresh_token, null: false, default: ""
    end
    add_index :oauth_access_tokens, :token, unique: true
    add_index :oauth_access_tokens, :refresh_token, unique: true
    add_index :oauth_access_tokens, :resource_owner_id
    add_foreign_key :oauth_access_tokens, :workspace_memberships, column: :resource_owner_id
  end
end
