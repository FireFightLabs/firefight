json.agents @agents do |agent|
  json.partial! "api/v1/agents/agent", agent: agent
end
