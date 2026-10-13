json.skill do
  json.partial! "api/v1/skills/skill", skill: @skill, full: true
end
