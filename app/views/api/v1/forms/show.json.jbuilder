json.form @form.slug
json.name @form.name
json.fields @form.resolved_fields(include_hidden: true) do |field|
  json.name field.source_name
  json.slug field.system_field_key || field.incident_field_definition&.slug
  json.source field.field_source_kind
  json.visible field.visibility_mode == IncidentFormField::VISIBILITY_MODE_VISIBLE
  json.required field.required_mode != IncidentFormField::REQUIRED_MODE_OPTIONAL
  json.locked field.locked_required?
  json.conditions field.incident_conditions do |condition|
    json.(condition, :condition_field, :operator, :values)
  end
end
