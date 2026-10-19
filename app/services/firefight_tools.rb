# Firefight's own tools, by the names agents call them and as the one list the MCP server, Halon, workflows and fixes
# read. Each tool is an MCP tool class, since MCP is how outside agents call them.
module FirefightTools
  SEARCH_INCIDENTS = "search_incidents".freeze
  SEARCH_SIMILAR = "search_similar".freeze
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
  LIST_MEMBER_ACCESS = "list_member_access".freeze
  SET_MEMBER_ACCESS = "set_member_access".freeze
  UPSERT_APPROVAL_RULE = "upsert_approval_rule".freeze
  DELETE_APPROVAL_RULE = "delete_approval_rule".freeze
  LIST_UNATTENDED_RULES = "list_unattended_rules".freeze
  UPSERT_UNATTENDED_RULE = "upsert_unattended_rule".freeze
  DELETE_UNATTENDED_RULE = "delete_unattended_rule".freeze
  LIST_ALLOWANCES = "list_allowances".freeze
  UPSERT_ALLOWANCE = "upsert_allowance".freeze
  DELETE_ALLOWANCE = "delete_allowance".freeze
  SEARCH_ACTIVITY = "search_activity".freeze
  CREATE_ACTION_ITEM = "create_action_item".freeze
  ASSIGN_ACTION_ITEM = "assign_action_item".freeze
  COMPLETE_ACTION_ITEM = "complete_action_item".freeze
  CREATE_ACTION_ITEM_ISSUE = "create_action_item_issue".freeze
  RENAME_ACTION_ITEM = "rename_action_item".freeze
  REOPEN_ACTION_ITEM = "reopen_action_item".freeze
  UNASSIGN_ACTION_ITEM = "unassign_action_item".freeze
  CLAIM_RUNBOOK_STEP = "claim_runbook_step".freeze
  LINK_INCIDENT = "link_incident".freeze
  GIVE_SHOUTOUT = "give_shoutout".freeze
  POST_TO_CHANNEL = "post_to_channel".freeze
  ESCALATE_INCIDENT = "escalate_incident".freeze
  PAGE_ON_CALL = "page_on_call".freeze
  INVITE_RESPONDERS = "invite_responders".freeze
  GET_WORKSPACE_CONFIG = "get_workspace_config".freeze
  UPDATE_WORKSPACE_SETTINGS = "update_workspace_settings".freeze
  UPDATE_PROTECTED_PATHS = "update_protected_paths".freeze
  LIST_INTEGRATIONS = "list_integrations".freeze
  GET_RESOURCE_MAP = ResourceMap::READ_TOOL
  FIND_RESOURCES = "find_resources".freeze
  SEARCH_MAP = "search_map".freeze
  GET_RESOURCE = "get_resource".freeze
  GET_RESOURCE_LINKS = "get_resource_links".freeze
  GET_RESOURCE_NEIGHBOURS = "get_resource_neighbours".freeze
  TRAVERSE_RESOURCE_MAP = "traverse_resource_map".freeze
  BLAST_RADIUS = "blast_radius".freeze
  RESOURCE_MAP_STATS = "resource_map_stats".freeze
  CHECK_STATUS_PAGE = "check_status_page".freeze
  BLIND_SPOTS = "blind_spots".freeze
  SUGGEST_RESOURCE_LINK = "suggest_resource_link".freeze
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
  UPSERT_OUTBOUND_WEBHOOK = "upsert_outbound_webhook".freeze
  DELETE_OUTBOUND_WEBHOOK = "delete_outbound_webhook".freeze
  TEST_OUTBOUND_WEBHOOK = "test_outbound_webhook".freeze
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
  START_INVESTIGATION = "start_investigation".freeze
  GET_INVESTIGATION = "get_investigation".freeze
  GET_HALON_PERFORMANCE = "get_halon_performance".freeze
  ASK_HALON = "ask_halon".freeze
  GET_HALON_ANSWER = "get_halon_answer".freeze
  LIST_WATCHES = "list_watches".freeze
  STOP_WATCH = "stop_watch".freeze
  LIST_NOTICES = "list_notices".freeze
  UPSERT_CATALOG_TYPE = "upsert_catalog_type".freeze
  DELETE_CATALOG_TYPE = "delete_catalog_type".freeze
  LIST_HANDBOOK_PAGES = "list_handbook_pages".freeze
  GET_HANDBOOK_PAGE = "get_handbook_page".freeze
  UPSERT_HANDBOOK_PAGE = "upsert_handbook_page".freeze
  DELETE_HANDBOOK_PAGE = "delete_handbook_page".freeze
  LIST_WORKFLOWS = "list_workflows".freeze
  CREATE_WORKFLOW = "create_workflow".freeze
  RUN_WORKFLOW = "run_workflow".freeze
  UPDATE_WORKFLOW_SETTINGS = "update_workflow_settings".freeze
  UPDATE_WORKFLOW = "update_workflow".freeze
  LIST_SKILLS = "list_skills".freeze
  GET_SKILL = "get_skill".freeze
  UPSERT_SKILL = "upsert_skill".freeze
  DELETE_SKILL = "delete_skill".freeze

  # Every tool the workspace has, leaving out one behind a flag it does not have.
  def self.available_in(workspace) = all.select { |tool_class| tool_class.offered_in?(workspace) }

  # The tools a fix's step may run: offered here, changes something, and one Halon may call.
  def self.for_fixes(workspace)
    available_in(workspace).reject do |tool_class|
      tool_class.annotations_value&.read_only_hint == true || Chat::Tools::Groups::NOT_FOR_HALON.include?(tool_class.name_value.to_s)
    end
  end

  def self.for_fix(workspace, name) = for_fixes(workspace).find { |tool_class| tool_class.name_value.to_s == name.to_s }

  def self.all
    [ Mcp::Tools::SearchIncidents, Mcp::Tools::SearchSimilar, Mcp::Tools::GetIncident, Mcp::Tools::SearchAlerts, Mcp::Tools::SearchCatalog, Mcp::Tools::EvaluateRouting,
      Mcp::Tools::SearchRunbooks, Mcp::Tools::GetRunbook, Mcp::Tools::UpsertCatalogEntry, Mcp::Tools::DeleteCatalogEntry,
      Mcp::Tools::UpsertRoutingRule, Mcp::Tools::DeleteRoutingRule, Mcp::Tools::UpdateRoutingConfig, Mcp::Tools::UpsertRunbook,
      Mcp::Tools::AssignIncidentRole, Mcp::Tools::AttachRunbook, Mcp::Tools::DismissTimelineNote,
      Mcp::Tools::DeclareIncident, Mcp::Tools::PostIncidentUpdate, Mcp::Tools::ResolveIncident, Mcp::Tools::CancelIncident, Mcp::Tools::ReopenIncident,
      Mcp::Tools::SearchApprovals, Mcp::Tools::ApproveApproval, Mcp::Tools::DenyApproval,
      Mcp::Tools::GetForm, Mcp::Tools::UpsertCustomField, Mcp::Tools::UpsertFormField,
      Mcp::Tools::ListAbilities, Mcp::Tools::ListPrincipals, Mcp::Tools::UpsertPermissionSet, Mcp::Tools::DeletePermissionSet, Mcp::Tools::GrantAbility, Mcp::Tools::RevokeGrant,
      Mcp::Tools::ListMemberAccess, Mcp::Tools::SetMemberAccess,
      Mcp::Tools::UpsertApprovalRule, Mcp::Tools::DeleteApprovalRule, Mcp::Tools::ListUnattendedRules, Mcp::Tools::UpsertUnattendedRule, Mcp::Tools::DeleteUnattendedRule,
      Mcp::Tools::ListAllowances, Mcp::Tools::UpsertAllowance, Mcp::Tools::DeleteAllowance, Mcp::Tools::SearchActivity,
      Mcp::Tools::CreateActionItem, Mcp::Tools::AssignActionItem, Mcp::Tools::CompleteActionItem, Mcp::Tools::RenameActionItem, Mcp::Tools::ReopenActionItem, Mcp::Tools::UnassignActionItem,
      Mcp::Tools::CreateActionItemIssue, Mcp::Tools::ClaimRunbookStep,
      Mcp::Tools::LinkIncident, Mcp::Tools::GiveShoutout, Mcp::Tools::EscalateIncident, Mcp::Tools::PageOnCall, Mcp::Tools::InviteResponders, Mcp::Tools::PostToChannel,
      Mcp::Tools::GetWorkspaceConfig, Mcp::Tools::UpdateWorkspaceSettings, Mcp::Tools::UpdateProtectedPaths, Mcp::Tools::ListIntegrations, Mcp::Tools::GetResourceMap, Mcp::Tools::SuggestResourceLink,
      Mcp::Tools::FindResources, Mcp::Tools::SearchMap, Mcp::Tools::GetResource, Mcp::Tools::GetResourceLinks, Mcp::Tools::GetResourceNeighbours, Mcp::Tools::TraverseResourceMap, Mcp::Tools::BlastRadius, Mcp::Tools::ResourceMapStats,
      Mcp::Tools::CheckStatusPage, Mcp::Tools::BlindSpots,
      Mcp::Tools::UpsertSeverity, Mcp::Tools::DeleteSeverity, Mcp::Tools::UpsertStatus, Mcp::Tools::DeleteStatus,
      Mcp::Tools::UpsertIncidentType, Mcp::Tools::DeleteIncidentType, Mcp::Tools::UpsertIncidentRole, Mcp::Tools::DeleteIncidentRole,
      Mcp::Tools::UpsertAlertSource, Mcp::Tools::DeleteAlertSource, Mcp::Tools::UpsertOutboundWebhook, Mcp::Tools::DeleteOutboundWebhook, Mcp::Tools::TestOutboundWebhook,
      Mcp::Tools::ListAgents, Mcp::Tools::UpsertAgent, Mcp::Tools::RotateAgentToken, Mcp::Tools::RevokeAgentToken, Mcp::Tools::DeleteAgent,
      Mcp::Tools::ListApiKeys, Mcp::Tools::UpsertApiKey, Mcp::Tools::DeleteApiKey,
      Mcp::Tools::GetPostmortem, Mcp::Tools::StartPostmortem, Mcp::Tools::UpdatePostmortem, Mcp::Tools::SetPostmortemStatus,
      Mcp::Tools::GetIncidentTranscript, Mcp::Tools::UpsertCatalogType, Mcp::Tools::DeleteCatalogType,
      Mcp::Tools::StartInvestigation, Mcp::Tools::GetInvestigation, Mcp::Tools::GetHalonPerformance, Mcp::Tools::AskHalon, Mcp::Tools::GetHalonAnswer, Mcp::Tools::ListWatches, Mcp::Tools::StopWatch, Mcp::Tools::ListNotices,
      Mcp::Tools::ListHandbookPages, Mcp::Tools::GetHandbookPage, Mcp::Tools::UpsertHandbookPage, Mcp::Tools::DeleteHandbookPage,
      Mcp::Tools::ListWorkflows, Mcp::Tools::CreateWorkflow, Mcp::Tools::RunWorkflow, Mcp::Tools::UpdateWorkflowSettings, Mcp::Tools::UpdateWorkflow,
      Mcp::Tools::ListSkills, Mcp::Tools::GetSkill, Mcp::Tools::UpsertSkill, Mcp::Tools::DeleteSkill ]
  end
end
