module Mcp
  # Tool name constants + the registry handed to MCP::Server. Names are the
  # wire-level identifiers agents call; never use raw strings elsewhere.
  module Tools
    SEARCH_INCIDENTS = "search_incidents".freeze
    GET_INCIDENT = "get_incident".freeze
    SEARCH_ALERTS = "search_alerts".freeze
    SEARCH_CATALOG = "search_catalog".freeze
    EVALUATE_ROUTING = "evaluate_routing".freeze

    def self.all
      [ SearchIncidents, GetIncident, SearchAlerts, SearchCatalog, EvaluateRouting ]
    end
  end
end
