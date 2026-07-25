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
    UPSERT_CATALOG_ENTRY = "upsert_catalog_entry".freeze
    DELETE_CATALOG_ENTRY = "delete_catalog_entry".freeze
    UPSERT_ROUTING_RULE = "upsert_routing_rule".freeze
    DELETE_ROUTING_RULE = "delete_routing_rule".freeze
    UPDATE_ROUTING_CONFIG = "update_routing_config".freeze
    UPSERT_RUNBOOK = "upsert_runbook".freeze
    SEARCH_APPROVALS = "search_approvals".freeze
    APPROVE_APPROVAL = "approve_approval".freeze
    DENY_APPROVAL = "deny_approval".freeze

    def self.all
      [ SearchIncidents, GetIncident, SearchAlerts, SearchCatalog, EvaluateRouting,
        SearchRunbooks, GetRunbook, UpsertCatalogEntry, DeleteCatalogEntry,
        UpsertRoutingRule, DeleteRoutingRule, UpdateRoutingConfig, UpsertRunbook,
        SearchApprovals, ApproveApproval, DenyApproval ]
    end
  end
end
