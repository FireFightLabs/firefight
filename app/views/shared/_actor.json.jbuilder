json.id actor.id
json.type actor.actor_kind
json.name actor.actor_display_name
json.email actor.respond_to?(:email) ? actor.email : nil
