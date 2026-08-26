json.(custom_field, :id, :slug, :name, :field_type, :option_source)
if custom_field.selectable?
  json.options custom_field.selectable_values.map { |id, label| { id: id, label: label } }
end
json.catalog_type_id custom_field.catalog_type_id if custom_field.catalog_options?
