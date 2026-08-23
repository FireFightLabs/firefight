# A relationship carried two identities: the attribute definition it belongs
# to and a string copy of that definition's slug. Only the definition is
# written by the app, so the copy and the position column it never used go.
class KeyCatalogRelationshipsOnTheirDefinition < ActiveRecord::Migration[8.1]
  def up
    execute "DELETE FROM catalog_entry_relationships WHERE catalog_attribute_definition_id IS NULL"
    change_column_null :catalog_entry_relationships, :catalog_attribute_definition_id, false
    remove_index :catalog_entry_relationships, name: "index_catalog_relationships_uniqueness"
    remove_index :catalog_entry_relationships, name: "index_catalog_relationships_single_ref"
    add_index :catalog_entry_relationships, [ :source_entry_id, :catalog_attribute_definition_id ],
              unique: true, name: "index_catalog_relationships_single_ref"
    remove_column :catalog_entry_relationships, :relationship_key
    remove_column :catalog_entry_relationships, :position
  end

  def down
    add_column :catalog_entry_relationships, :position, :integer
    add_column :catalog_entry_relationships, :relationship_key, :string
    execute <<~SQL
      UPDATE catalog_entry_relationships r
      SET relationship_key = d.slug
      FROM catalog_attribute_definitions d
      WHERE d.id = r.catalog_attribute_definition_id
    SQL
    change_column_null :catalog_entry_relationships, :relationship_key, false
    remove_index :catalog_entry_relationships, name: "index_catalog_relationships_single_ref"
    add_index :catalog_entry_relationships, [ :source_entry_id, :catalog_attribute_definition_id ],
              unique: true, name: "index_catalog_relationships_single_ref", where: "catalog_attribute_definition_id IS NOT NULL"
    add_index :catalog_entry_relationships, [ :source_entry_id, :target_entry_id, :relationship_key ],
              unique: true, name: "index_catalog_relationships_uniqueness"
    change_column_null :catalog_entry_relationships, :catalog_attribute_definition_id, true
  end
end
