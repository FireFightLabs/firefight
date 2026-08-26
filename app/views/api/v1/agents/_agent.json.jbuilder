json.(agent, :id, :name, :slug, :description, :enabled)
json.granted_abilities agent.ability_grants.size
json.tokens agent.live_api_keys do |key|
  json.prefix key.token_prefix
  json.created_at key.created_at.utc.iso8601
  json.last_used_at key.last_used_at&.utc&.iso8601
end
