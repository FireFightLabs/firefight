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
    CREATE_ACTION_ITEM = "create_action_item".freeze
    ASSIGN_ACTION_ITEM = "assign_action_item".freeze
    COMPLETE_ACTION_ITEM = "complete_action_item".freeze
    CLAIM_RUNBOOK_STEP = "claim_runbook_step".freeze
    LINK_INCIDENT = "link_incident".freeze
    GIVE_SHOUTOUT = "give_shoutout".freeze
    ESCALATE_INCIDENT = "escalate_incident".freeze
    INVITE_RESPONDERS = "invite_responders".freeze
    GET_WORKSPACE_CONFIG = "get_workspace_config".freeze
    UPSERT_SEVERITY = "upsert_severity".freeze
    DELETE_SEVERITY = "delete_severity".freeze
    UPSERT_STATUS = "upsert_status".freeze
    DELETE_STATUS = "delete_status".freeze
    UPSERT_INCIDENT_TYPE = "upsert_incident_type".freeze
    DELETE_INCIDENT_TYPE = "delete_incident_type".freeze
    UPSERT_INCIDENT_ROLE = "upsert_incident_role".freeze
    DELETE_INCIDENT_ROLE = "delete_incident_role".freeze
    UPSERT_ALERT_SOURCE = "upsert_alert_source".freeze
    DELETE_ALERT_SOURCE = "delete_alert_source".freeze
    UPSERT_WEBHOOK = "upsert_webhook".freeze
    DELETE_WEBHOOK = "delete_webhook".freeze
    LIST_AGENTS = "list_agents".freeze
    UPSERT_AGENT = "upsert_agent".freeze
    ROTATE_AGENT_TOKEN = "rotate_agent_token".freeze
    REVOKE_AGENT_TOKEN = "revoke_agent_token".freeze
    DELETE_AGENT = "delete_agent".freeze
    LIST_API_KEYS = "list_api_keys".freeze
    UPSERT_API_KEY = "upsert_api_key".freeze
    DELETE_API_KEY = "delete_api_key".freeze
    GET_POSTMORTEM = "get_postmortem".freeze
    START_POSTMORTEM = "start_postmortem".freeze
    UPDATE_POSTMORTEM = "update_postmortem".freeze
    SET_POSTMORTEM_STATUS = "set_postmortem_status".freeze
    GET_INCIDENT_TRANSCRIPT = "get_incident_transcript".freeze

    def self.all
      [ SearchIncidents, GetIncident, SearchAlerts, SearchCatalog, EvaluateRouting,
        SearchRunbooks, GetRunbook, UpsertCatalogEntry, DeleteCatalogEntry,
        UpsertRoutingRule, DeleteRoutingRule, UpdateRoutingConfig, UpsertRunbook,
        AssignIncidentRole, AttachRunbook, DismissTimelineNote,
        DeclareIncident, PostIncidentUpdate, ResolveIncident, CancelIncident, ReopenIncident,
        SearchApprovals, ApproveApproval, DenyApproval,
        GetForm, UpsertCustomField, UpsertFormField,
        ListAbilities, ListPrincipals, UpsertPermissionSet, DeletePermissionSet, GrantAbility, RevokeGrant,
        UpsertApprovalRule, DeleteApprovalRule, SearchActivity,
        CreateActionItem, AssignActionItem, CompleteActionItem, ClaimRunbookStep,
        LinkIncident, GiveShoutout, EscalateIncident, InviteResponders,
        GetWorkspaceConfig,
        UpsertSeverity, DeleteSeverity, UpsertStatus, DeleteStatus,
        UpsertIncidentType, DeleteIncidentType, UpsertIncidentRole, DeleteIncidentRole,
        UpsertAlertSource, DeleteAlertSource, UpsertWebhook, DeleteWebhook,
        ListAgents, UpsertAgent, RotateAgentToken, RevokeAgentToken, DeleteAgent,
        ListApiKeys, UpsertApiKey, DeleteApiKey,
        GetPostmortem, StartPostmortem, UpdatePostmortem, SetPostmortemStatus,
        GetIncidentTranscript ]
    end
  end
end
