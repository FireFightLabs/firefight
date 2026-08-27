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
    CUSTOM_FIELDS = "#{BASE}/customization/custom-fields.md".freeze
    INCIDENT_FORMS = "#{BASE}/customization/incident-forms.md".freeze
    MCP_SERVER = "#{BASE}/api/mcp-server.md".freeze
    PERMISSIONS = "#{BASE}/gateway/permissions.md".freeze
    APPROVALS = "#{BASE}/gateway/approvals.md".freeze
    ACTIVITY = "#{BASE}/gateway/activity.md".freeze
  end
end
