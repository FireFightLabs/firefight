json.(api_key, :id, :name, :active)
json.prefix api_key.token_prefix
json.expires_at api_key.expires_at&.utc&.iso8601
json.last_used_at api_key.last_used_at&.utc&.iso8601
json.permissions api_key.granted_permissions
