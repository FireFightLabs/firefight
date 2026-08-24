json.(type, :id, :slug, :name, :description, :kind)
json.attribute_definitions type.catalog_attribute_definitions.sort_by(&:position) do |attr_def|
  json.(attr_def, :slug, :name, :attribute_type, :required)
  json.role attr_def.role if attr_def.role.present?
  json.options attr_def.options if attr_def.select?
  json.reference_type_id attr_def.reference_type_id if attr_def.reference?
end
