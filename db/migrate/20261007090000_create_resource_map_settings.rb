# Where a service's settings point and where each store says it can be reached, as keyed digests, so the map can link a
# service to the database its DATABASE_URL names without keeping the value. A use keeps the setting's name only, and a
# link keeps the names of the settings that point along it.
class CreateResourceMapSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :resource_map_uses, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true, index: false
      t.references :resource, type: :uuid, null: false, foreign_key: { to_table: :resource_map_resources, on_delete: :cascade }, index: true
      t.references :integration_environment, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :variable, null: false
      t.string :fingerprint
      t.string :domain_fingerprint
      t.string :database_fingerprint
      t.string :tenant_fingerprint
      t.string :scheme
      t.integer :port
      t.datetime :last_seen_at, null: false
      t.timestamps
    end
    add_index :resource_map_uses, %i[integration_environment_id resource_id variable], unique: true, name: "index_resource_map_uses_identity"
    add_index :resource_map_uses, %i[workspace_id fingerprint], name: "index_resource_map_uses_on_workspace_fingerprint"
    add_index :resource_map_uses, %i[workspace_id domain_fingerprint], name: "index_resource_map_uses_on_workspace_domain_fingerprint"

    create_table :resource_map_endpoints, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true, index: false
      t.references :resource, type: :uuid, null: false, foreign_key: { to_table: :resource_map_resources, on_delete: :cascade }, index: true
      t.references :integration_environment, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :fingerprint, null: false
      # The fingerprint is of a domain any host one label under it answers for, such as a shared pooler's.
      t.boolean :within_domain, null: false, default: false
      t.string :database_fingerprint
      t.string :tenant_fingerprint
      t.integer :port, null: false
      t.datetime :last_seen_at, null: false
      t.timestamps
    end
    add_index :resource_map_endpoints, %i[integration_environment_id resource_id fingerprint within_domain database_fingerprint tenant_fingerprint],
              unique: true, nulls_not_distinct: true, name: "index_resource_map_endpoints_identity"
    add_index :resource_map_endpoints, %i[workspace_id fingerprint], name: "index_resource_map_endpoints_on_workspace_fingerprint"

    add_column :resource_map_links, :variables, :jsonb, null: false, default: []
  end
end
