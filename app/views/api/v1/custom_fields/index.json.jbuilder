json.custom_fields @custom_fields do |field|
  json.(field, :id, :slug, :name, :field_type, :option_source)
  if field.selectable?
    json.options field.selectable_values.map { |id, label| { id: id, label: label } }
  end
  json.catalog_type_id field.catalog_type_id if field.catalog_options?
end
