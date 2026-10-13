json.skills @skills do |skill|
  json.partial! "api/v1/skills/skill", skill: skill
end
