json.id grant.id
json.principal do
  json.kind grant.principal.actor_kind
  json.id grant.principal_id
  json.name grant.principal.actor_display_name
end
json.ability grant.action&.key
json.permission_set grant.role&.slug
json.environments grant.workspace.environment_entries.where(id: grant.environment_ids).pluck(:slug)
json.expires_at grant.expires_at&.utc&.iso8601
json.expired grant.expired?
json.created_at grant.created_at.utc.iso8601
