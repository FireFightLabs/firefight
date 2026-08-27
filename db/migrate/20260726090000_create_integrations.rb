class CreateIntegrations < ActiveRecord::Migration[8.1]
  def change
    create_table :integrations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :workspace_id, null: false
      t.string :kind, null: false
      t.string :provider, null: false
      t.string :name, null: false
      # Namespaces this instance's action keys (github.pr_list). Immutable.
      t.string :slug, null: false
      t.jsonb :settings, default: {}, null: false
      t.datetime :disabled_at
      t.datetime :deleted_at

      t.timestamps
    end
    add_index :integrations, [ :workspace_id, :slug ], unique: true
    add_foreign_key :integrations, :workspaces

    create_table :integration_environments, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :integration_id, null: false
      # nil = not environment-scoped (e.g. GitHub), the "global" row.
      t.uuid :catalog_entry_id
      t.text :credentials
      t.jsonb :base_config, default: {}, null: false
      t.boolean :enabled, default: true, null: false
      t.string :health_status, default: "unknown", null: false
      t.datetime :health_checked_at

      t.timestamps
    end
    add_index :integration_environments, [ :integration_id, :catalog_entry_id ], unique: true,
              where: "catalog_entry_id IS NOT NULL", name: "index_integration_environments_on_env"
    add_index :integration_environments, :integration_id, unique: true,
              where: "catalog_entry_id IS NULL", name: "index_integration_environments_global"
    add_foreign_key :integration_environments, :integrations
    add_foreign_key :integration_environments, :catalog_entries

    create_table :integration_tools, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :integration_id, null: false
      t.string :name, null: false
      t.string :description
      t.jsonb :params_schema, default: {}, null: false
      t.jsonb :spec, default: {}, null: false
      t.boolean :read_only, default: false, null: false
      t.boolean :enabled, default: false, null: false

      t.timestamps
    end
    add_index :integration_tools, [ :integration_id, :name ], unique: true
    add_foreign_key :integration_tools, :integrations
  end
end
