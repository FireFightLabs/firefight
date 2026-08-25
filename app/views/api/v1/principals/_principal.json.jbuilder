json.kind principal.actor_kind
json.id principal.id
json.name principal.actor_display_name
json.implicit_authority principal.implicit_authority.to_s
json.grants principal.ability_grants, partial: "api/v1/grants/grant", as: :grant
