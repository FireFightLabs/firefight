json.api_keys @api_keys do |api_key|
  json.partial! "api/v1/api_keys/api_key", api_key: api_key
end
