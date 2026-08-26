json.action_items @action_items do |action_item|
  json.partial! "api/v1/action_items/action_item", action_item: action_item
end

json.pagination @pagination
