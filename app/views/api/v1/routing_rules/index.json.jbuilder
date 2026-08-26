json.routing_rules @rules do |rule|
  json.partial! "api/v1/routing_rules/routing_rule", routing_rule: rule
end
