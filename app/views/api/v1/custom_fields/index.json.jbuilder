json.custom_fields @custom_fields do |field|
  json.partial! "api/v1/custom_fields/custom_field", custom_field: field
end
