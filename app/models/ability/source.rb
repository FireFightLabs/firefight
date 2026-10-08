module Ability
  # Where a gateway call came from, as a person reads it wherever the ledger is shown.
  module Source
    LABELS = {
      AbilityGateway::SOURCE_API => "API", AbilityGateway::SOURCE_MCP => "MCP", AbilityGateway::SOURCE_SLACK => "Slack",
      AbilityGateway::SOURCE_WEB => "Dashboard", AbilityGateway::SOURCE_INVESTIGATION => "Investigation",
      AbilityGateway::SOURCE_CONVERSATION => "Halon chat", AbilityGateway::SOURCE_MAP_SWEEP => "Map sweep",
      AbilityGateway::SOURCE_HEALTH_CHECK => "Health check", AbilityGateway::SOURCE_CODE_AGENT => "Coding agent",
      AbilityGateway::SOURCE_ISSUE_SYNC => "Issue sync", AbilityGateway::SOURCE_WATCH => "Halon watch"
    }.freeze

    def self.label(source) = LABELS.fetch(source.to_s, source.to_s.humanize).presence
  end
end
