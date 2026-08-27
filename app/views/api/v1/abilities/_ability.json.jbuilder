json.(ability, :key, :kind, :risk_level, :reversible)
json.group ability.system? ? "Firefight" : ability.source&.integration&.name.to_s
json.approval_exempt Ability::Action.approval_exempt?(ability.key)
