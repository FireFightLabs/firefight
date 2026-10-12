people = ->(ids) { ids.filter_map { |id| names[id] }.map { |member| { id: member.id, name: member.display_name } } }
json.connection do
  json.id connection.integration.id
  json.name connection.integration.display_name
end
{ read: connection.read, change: connection.change }.each do |kind, standing|
  json.set! kind do
    json.permission_set standing.role.slug
    json.choice standing.choice
    json.people people.call(standing.people_ids)
    json.left_out people.call(standing.left_out_ids)
    json.through(standing.through.map { |access| { permission_set: access.role_slug, name: access.role_name, people: people.call(access.people_ids) } })
    json.unavailable_reason standing.role.member_access_unavailable_reason
  end
end
