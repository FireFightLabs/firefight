module Mcp
  # Tool name constants + the registry handed to MCP::Server. Names are the
  # wire-level identifiers agents call; never use raw strings elsewhere.
  module Tools
    SEARCH_INCIDENTS = "search_incidents".freeze
    GET_INCIDENT = "get_incident".freeze
    SEARCH_ALERTS = "search_alerts".freeze
    SEARCH_CATALOG = "search_catalog".freeze
    EVALUATE_ROUTING = "evaluate_routing".freeze
    SEARCH_RUNBOOKS = "search_runbooks".freeze
    GET_RUNBOOK = "get_runbook".freeze

    def self.all
      [ SearchIncidents, GetIncident, SearchAlerts, SearchCatalog, EvaluateRouting,
        SearchRunbooks, GetRunbook ]
    end
  end
end
