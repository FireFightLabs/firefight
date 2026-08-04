class RenameDefinitionKeysToSlugs < ActiveRecord::Migration[8.1]
  def change
    rename_column :incident_field_definitions, :key, :slug
    rename_column :catalog_attribute_definitions, :key, :slug

    rename_index :incident_field_definitions,
      "index_incident_field_definitions_on_workspace_and_key_active",
      "index_incident_field_definitions_on_workspace_and_slug_active"
  end
end
