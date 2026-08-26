json.form @form.slug
json.field @form_field.source_name
json.visible @form_field.visibility_mode == IncidentFormField::VISIBILITY_MODE_VISIBLE
json.required @form_field.required_mode != IncidentFormField::REQUIRED_MODE_OPTIONAL
json.locked @form_field.locked_required?
json.conditions @form_field.incident_conditions.count
