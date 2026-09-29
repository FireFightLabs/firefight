class CreateResourceMap < ActiveRecord::Migration[8.1]
  def change
    create_table :resource_map_resources, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true, index: false
      t.references :integration_environment, type: :uuid, foreign_key: { on_delete: :nullify }
      t.string :provider, null: false
      t.string :account, null: false
      t.string :kind, null: false
      t.string :external_id, null: false
      t.string :name, null: false
      t.string :status
      t.string :url
      t.jsonb :details, null: false, default: {}
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :removed_at
      t.timestamps
    end
    add_index :resource_map_resources, %i[workspace_id provider account kind external_id], unique: true, name: "index_resource_map_resources_identity"

    create_table :resource_map_links, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true, index: false
      t.references :from_resource, type: :uuid, null: false, foreign_key: { to_table: :resource_map_resources, on_delete: :cascade }
      t.references :to_resource, type: :uuid, null: false, foreign_key: { to_table: :resource_map_resources, on_delete: :cascade }
      t.string :relation, null: false
      t.string :origin, null: false
      t.references :integration_environment, type: :uuid, foreign_key: { on_delete: :nullify }
      t.datetime :last_seen_at, null: false
      t.timestamps
    end
    add_index :resource_map_links, %i[from_resource_id to_resource_id relation], unique: true, name: "index_resource_map_links_identity"
    add_index :resource_map_links, :workspace_id

    add_column :integration_environments, :map_swept_at, :datetime
    add_column :integration_environments, :map_error, :string
    add_column :integration_environments, :map_gaps, :jsonb, null: false, default: []
  end
end
