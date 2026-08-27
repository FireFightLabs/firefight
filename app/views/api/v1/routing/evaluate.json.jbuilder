json.matched @routed.matched?
json.matched_rule_priority @routed.matched_rule&.priority
json.outcome @routed.outcome
json.context @routed.context
json.trace @routed.trace
json.role_warnings @role_warnings if @role_warnings.any?
