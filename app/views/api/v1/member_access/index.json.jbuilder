json.connections @overview.connections do |connection|
  json.partial! "api/v1/member_access/connection", connection: connection, names: @overview.members.index_by(&:id)
end
