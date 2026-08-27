json.events @events do |event|
  json.partial! "api/v1/timeline/event", event: event
end

json.pagination @pagination
