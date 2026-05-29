json.(entry, :id, :name, :slug, :source, :external_id)
json.catalog_type_id entry.catalog_type_id
json.attributes entry.entry_attributes
json.references entry.outgoing_relationships do |rel|
  json.key rel.relationship_key
  json.target_entry_id rel.target_entry_id
  json.target_name rel.target_entry.name
end
