json.(permission_set, :slug, :name, :description)
json.built_in permission_set.built_in?
json.abilities permission_set.actions.map(&:key).sort
json.grant_count permission_set.grants.size
json.created_at permission_set.created_at.utc.iso8601
json.updated_at permission_set.updated_at.utc.iso8601
