json.custom_fields @custom_fields do |field|
  json.(field, :id, :key, :name, :field_type, :option_source)
  json.options field.options if field.fixed_options?
  json.catalog_type_id field.catalog_type_id if field.catalog_options?
end
