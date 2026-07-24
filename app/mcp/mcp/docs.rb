module Mcp
  # Public product-doc URLs surfaced to agents via server instructions, tool
  # descriptions, and error messages. The .md URLs return raw markdown.
  module Docs
    BASE = "https://firefight.app/docs".freeze
    INDEX = "https://firefight.app/llms.txt".freeze

    INCIDENTS = "#{BASE}/incidents/concepts.md".freeze
    ALERTS = "#{BASE}/alerts/how-alerts-work.md".freeze
    ROUTING_RULES = "#{BASE}/alerts/routing-rules.md".freeze
    CATALOG = "#{BASE}/catalog/overview.md".freeze
    RUNBOOKS = "#{BASE}/incidents/runbooks.md".freeze
    MCP_SERVER = "#{BASE}/api/mcp-server.md".freeze
  end
end
