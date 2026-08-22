module Identifiers
  # Modal callback_ids
  INCIDENT_CREATION_MODAL = "incident_creation_modal"
  INCIDENT_HOME_MODAL = "incident_home_modal"
  SHARE_INCIDENTS_CHANNEL_MODAL = "share_incidents_channel_modal"
  UPDATE_SUMMARY_MODAL = "update_summary_modal"
  SET_LEAD_MODAL = "set_lead_modal"
  SET_ROLES_MODAL = "set_roles_modal"
  INCIDENT_UPDATE_MODAL = "incident_update_modal"
  SEND_INCIDENT_UPDATE = "send_incident_update"
  INCIDENT_ACTIONS_MODAL = "incident_actions_modal"
  RUNBOOK_DETAIL_MODAL = "runbook_detail_modal"
  ATTACH_RUNBOOK_MODAL = "attach_runbook_modal"
  INCIDENT_FOLLOWUPS_MODAL = "incident_followups_modal"
  CREATE_ACTION_MODAL = "create_action_modal"
  CREATE_FOLLOWUP_MODAL = "create_followup_modal"
  CANCEL_INCIDENT_MODAL = "cancel_incident_modal"
  CLOSE_INCIDENT_MODAL = "close_incident_modal"
  REOPEN_INCIDENT_MODAL = "reopen_incident_modal"
  LINK_INCIDENT_MODAL = "link_incident_modal"
  ESCALATE_INCIDENT_MODAL = "escalate_incident_modal"
  INVITE_RESPONDERS_MODAL = "invite_responders_modal"
  SHOUTOUT_MODAL = "shoutout_modal"
  TIMELINE_MODAL = "timeline_modal"

  # Shortcut callback_ids
  CREATE_INCIDENT_SHORTCUT = "create_incident_shortcut"

  # Slash command subcommands
  SUBCOMMAND_NEW        = "new"
  SUBCOMMAND_HOME       = "home"
  SUBCOMMAND_SUMMARY    = "summary"
  SUBCOMMAND_LEAD       = "lead"
  SUBCOMMAND_ROLE       = "role"
  SUBCOMMAND_ROLES      = "roles"
  SUBCOMMAND_STATUS     = "status"
  SUBCOMMAND_UPDATE     = "update"
  SUBCOMMAND_SEVERITY   = "severity"
  SUBCOMMAND_ESCALATE   = "escalate"
  SUBCOMMAND_INVITE     = "invite"
  SUBCOMMAND_ACTION     = "action"
  SUBCOMMAND_ACTIONS    = "actions"
  SUBCOMMAND_FOLLOWUP   = "followup"
  SUBCOMMAND_FOLLOWUPS  = "followups"
  SUBCOMMAND_LINK       = "link"
  SUBCOMMAND_RELATE     = "relate"
  SUBCOMMAND_DUPLICATE  = "duplicate"
  SUBCOMMAND_CLOSE      = "close"
  SUBCOMMAND_RESOLVE    = "resolve"
  SUBCOMMAND_CANCEL     = "cancel"
  SUBCOMMAND_REOPEN     = "reopen"
  SUBCOMMAND_OPEN       = "open"
  SUBCOMMAND_POSTMORTEM = "postmortem"
  SUBCOMMAND_CATCHUP    = "catchup"
  SUBCOMMAND_TIMELINE   = "timeline"
  SUBCOMMAND_LIST       = "list"
  SUBCOMMAND_SHOUTOUT   = "shoutout"
  SUBCOMMAND_RUNBOOK    = "runbook"
  SUBCOMMAND_RUNBOOKS   = "runbooks"

  # Home modal action values
  HOME_ACTION_NEW        = "new"
  HOME_ACTION_STATUS     = "status"
  HOME_ACTION_SEVERITY   = "severity"
  HOME_ACTION_SUMMARY    = "summary"
  HOME_ACTION_ESCALATE   = "escalate"
  HOME_ACTION_INVITE     = "invite"
  HOME_ACTION_LEAD       = "lead"
  HOME_ACTION_ROLES      = "roles"
  HOME_ACTION_ACTIONS    = "actions"
  HOME_ACTION_CLOSE      = "close"
  HOME_ACTION_TIMELINE   = "timeline"
  HOME_ACTION_LIST       = "list"
  HOME_ACTION_POSTMORTEM = "postmortem"
  HOME_ACTION_RUNBOOK    = "runbook"

  # Block action_ids
  HOME_ACTION_SELECT = "home_action_select"
  SHARE_INCIDENTS_CHANNEL = "share_incidents_channel"
  PREVIEW_ANNOUNCEMENT = "preview_announcement"
  PREVIEW_HOMEPAGE_DISABLED = "preview_homepage_disabled"
  INCIDENT_HOMEPAGE = "incident_homepage"
  PREVIEW_SUBSCRIBE_DISABLED = "preview_subscribe_disabled"
  ACCEPT_INCIDENT = "accept_incident"
  CANCEL_INCIDENT = "cancel_incident"
  SET_INCIDENT_LEAD_SELF = "set_incident_lead_self"
  ROLE_SELECT = "role_select"

  # The roles modal renders one input block per configured role, so the
  # block_id carries the role it belongs to.
  ROLE_BLOCK_PREFIX = "role_block_"
  UPDATE_INCIDENT_SUMMARY = "update_incident_summary"
  ESCALATE_INCIDENT = "escalate_incident"
  PICK_UP_ACTION = "pick_up_action"
  MARK_ACTION_DONE = "mark_action_done"
  ADD_NEW_ACTION = "add_new_action"
  ADD_NEW_FOLLOWUP = "add_new_followup"
  CREATE_ACTION_FROM_REACTION = "create_action_from_reaction"
  CREATE_FOLLOWUP_FROM_REACTION = "create_followup_from_reaction"
  TIMELINE_PAGE = "timeline_page"
  # Retired, still routed so a timeline modal opened before the pager shipped
  # re-renders instead of dead-clicking.
  LOAD_MORE_TIMELINE = "load_more_timeline"
  ACKNOWLEDGE_ESCALATION = "acknowledge_escalation"
  SHOUTOUT_FROM_REACTION = "shoutout_from_reaction"
  INCIDENT_CREATION_SEVERITY_SELECT = "incident_creation_severity_select"
  INCIDENT_CREATION_TYPE_SELECT = "incident_creation_type_select"
  INCIDENT_CREATION_VISIBILITY_SELECT = "incident_creation_visibility_select"
  # Retired, still routed so buttons on older messages re-render the checklist.
  APPLY_RUNBOOK = "apply_runbook"
  CLAIM_RUNBOOK_STEP = "claim_runbook_step"
  VIEW_RUNBOOK = "view_runbook"
  ASSIGN_RUNBOOK_STEP = "assign_runbook_step"
  REASSIGN_ACTION = "reassign_action"
  # A users_select carries no value, so block_id holds the id it acts on.
  ACTION_BLOCK_PREFIX = "action_block_"
  RUNBOOK_STEP_BLOCK_PREFIX = "runbook_step_block_"
  APPROVE_ABILITY = "approve_ability"
  DENY_ABILITY = "deny_ability"

  # Slack event types (top-level Events API)
  EVENT_REACTION_ADDED  = "reaction_added"
  EVENT_MESSAGE         = "message"
  EVENT_PIN_ADDED       = "pin_added"
  EVENT_PIN_REMOVED     = "pin_removed"
  EVENT_APP_MENTION     = "app_mention"
  EVENT_MEMBER_JOINED   = "member_joined_channel"

  # Slack message subtypes (event["subtype"])
  MESSAGE_SUBTYPE_FILE_SHARE      = "file_share"
  MESSAGE_SUBTYPE_MESSAGE_CHANGED = "message_changed"
  MESSAGE_SUBTYPE_MESSAGE_DELETED = "message_deleted"

  def self.role_block_id(role)
    "#{ROLE_BLOCK_PREFIX}#{role.id}"
  end

  def self.role_id_from_block(block_id)
    block_id.delete_prefix(ROLE_BLOCK_PREFIX)
  end
end
