json.custom_fields @custom_fields do |field|
  json.(field, :id, :slug, :name, :field_type, :option_source)
  if field.fixed_options?
    json.options field.incident_field_options.active.ordered.map { |option| { id: option.id, label: option.label } }
  end
  json.catalog_type_id field.catalog_type_id if field.catalog_options?
end
