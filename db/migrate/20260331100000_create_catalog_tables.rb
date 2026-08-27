class CreateCatalogTables < ActiveRecord::Migration[8.1]
  def change
    create_table :catalog_types, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.string :kind, null: false
      t.string :system_key
      t.string :icon
      t.text :description
      t.string :color
      t.integer :position, null: false
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :catalog_types, [ :workspace_id, :slug ], unique: true
    add_index :catalog_types, [ :workspace_id, :system_key ], unique: true,
      where: "system_key IS NOT NULL"

    create_table :catalog_attribute_definitions, id: :uuid do |t|
      t.references :catalog_type, type: :uuid, null: false, foreign_key: true
      t.string :key, null: false
      t.string :name, null: false
      t.string :attribute_type, null: false
      t.boolean :required, null: false, default: false
      t.integer :position, null: false
      t.jsonb :config, null: false, default: {}
      t.timestamps
    end

    add_index :catalog_attribute_definitions, [ :catalog_type_id, :key ], unique: true,
      name: "index_catalog_attr_defs_on_type_and_key"

    create_table :catalog_entries, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.references :catalog_type, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.jsonb :attributes, null: false, default: {}
      t.string :source
      t.string :external_id
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :catalog_entries, [ :catalog_type_id, :slug ], unique: true
    add_index :catalog_entries, [ :workspace_id, :catalog_type_id ]
    add_index :catalog_entries, [ :workspace_id, :source, :external_id ], unique: true,
      where: "source IS NOT NULL AND external_id IS NOT NULL",
      name: "index_catalog_entries_external_identity"

    create_table :catalog_entry_relationships, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.references :source_entry, type: :uuid, null: false, foreign_key: { to_table: :catalog_entries }
      t.references :target_entry, type: :uuid, null: false, foreign_key: { to_table: :catalog_entries }
      t.references :catalog_attribute_definition, type: :uuid, null: true, foreign_key: true
      t.string :relationship_key, null: false
      t.integer :position
      t.timestamps
    end

    add_index :catalog_entry_relationships,
      [ :source_entry_id, :target_entry_id, :relationship_key ],
      unique: true,
      name: "index_catalog_relationships_uniqueness"

    add_index :catalog_entry_relationships,
      [ :source_entry_id, :catalog_attribute_definition_id ],
      unique: true,
      where: "catalog_attribute_definition_id IS NOT NULL",
      name: "index_catalog_relationships_single_ref"
  end
end
