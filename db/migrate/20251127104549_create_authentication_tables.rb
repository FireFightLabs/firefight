class CreateAuthenticationTables < ActiveRecord::Migration[8.1]
  def change
    # Enable UUID extension for PostgreSQL
    enable_extension 'pgcrypto' unless extension_enabled?('pgcrypto')

    # Workspaces table - platform-agnostic workspace management
    create_table :workspaces, id: :uuid do |t|
      t.string :platform, null: false, default: 'slack' # enum: 'slack', 'teams'
      t.string :platform_id, null: false # Slack team ID, Teams tenant ID, etc.
      t.string :name, null: false
      t.string :avatar_url
      t.jsonb :platform_data, default: {}, null: false # Platform-specific metadata
      t.text :access_token # Encrypted bot/workspace token
      t.text :refresh_token # Encrypted refresh token
      t.datetime :token_expires_at # Token expiration timestamp
      t.datetime :installed_at, null: false # When workspace was first connected

      t.timestamps
    end

    add_index :workspaces, [:platform, :platform_id], unique: true
    add_index :workspaces, :platform

    # Users table - application users
    create_table :users, id: :uuid do |t|
      t.string :email, null: false
      t.string :name, null: false
      t.string :avatar_url

      t.timestamps
    end

    add_index :users, :email, unique: true

    # Workspace memberships table - joins users to workspaces with roles
    create_table :workspace_memberships, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.string :platform_user_id, null: false # Slack user ID (U1234567), Teams user ID, etc.
      t.string :role, default: 'member', null: false # enum: 'member', 'admin', 'owner'
      t.jsonb :platform_data, default: {}, null: false # Platform-specific user data
      t.text :access_token # Encrypted user-level OAuth token
      t.text :refresh_token # Encrypted user-level refresh token
      t.datetime :token_expires_at # User token expiration
      t.datetime :joined_at, null: false # When user joined workspace

      t.timestamps
    end

    add_index :workspace_memberships, [:workspace_id, :platform_user_id],
              unique: true,
              name: 'index_workspace_memberships_on_workspace_and_platform_user'
    add_index :workspace_memberships, :role
  end
end
