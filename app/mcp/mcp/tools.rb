module Mcp
  # Tool name constants + the registry handed to MCP::Server. Names are the
  # wire-level identifiers agents call. Never use raw strings elsewhere.
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
    GET_FORM = "get_form".freeze
    UPSERT_CUSTOM_FIELD = "upsert_custom_field".freeze
    UPSERT_FORM_FIELD = "upsert_form_field".freeze
    ASSIGN_INCIDENT_ROLE = "assign_incident_role".freeze
    ATTACH_RUNBOOK = "attach_runbook".freeze
    DISMISS_TIMELINE_NOTE = "dismiss_timeline_note".freeze
    DECLARE_INCIDENT = "declare_incident".freeze
    POST_INCIDENT_UPDATE = "post_incident_update".freeze
    RESOLVE_INCIDENT = "resolve_incident".freeze
    CANCEL_INCIDENT = "cancel_incident".freeze
    REOPEN_INCIDENT = "reopen_incident".freeze
    SEARCH_APPROVALS = "search_approvals".freeze
    APPROVE_APPROVAL = "approve_approval".freeze
    DENY_APPROVAL = "deny_approval".freeze
    LIST_ABILITIES = "list_abilities".freeze
    LIST_PRINCIPALS = "list_principals".freeze
    UPSERT_PERMISSION_SET = "upsert_permission_set".freeze
    DELETE_PERMISSION_SET = "delete_permission_set".freeze
    GRANT_ABILITY = "grant_ability".freeze
    REVOKE_GRANT = "revoke_grant".freeze
    UPSERT_APPROVAL_RULE = "upsert_approval_rule".freeze
    DELETE_APPROVAL_RULE = "delete_approval_rule".freeze
    SEARCH_ACTIVITY = "search_activity".freeze

    def self.all
      [ SearchIncidents, GetIncident, SearchAlerts, SearchCatalog, EvaluateRouting,
        SearchRunbooks, GetRunbook, UpsertCatalogEntry, DeleteCatalogEntry,
        UpsertRoutingRule, DeleteRoutingRule, UpdateRoutingConfig, UpsertRunbook,
        AssignIncidentRole, AttachRunbook, DismissTimelineNote,
        DeclareIncident, PostIncidentUpdate, ResolveIncident, CancelIncident, ReopenIncident,
        SearchApprovals, ApproveApproval, DenyApproval,
        GetForm, UpsertCustomField, UpsertFormField,
        ListAbilities, ListPrincipals, UpsertPermissionSet, DeletePermissionSet, GrantAbility, RevokeGrant,
        UpsertApprovalRule, DeleteApprovalRule, SearchActivity ]
    end
  end
end
