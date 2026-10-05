# An item's issue in the workspace's tracker (Workspace::IssueSync). external_key and external_url name the issue once it
# is there, issue_integration is the connection that holds it, and issue_sync_state says where getting or keeping it
# stands, with issue_sync_note saying why in words a person reads. Each of the issue's title, status and assignee keeps
# the time of the last change either side made to it (issue_*_synced_at), so a change older than one already applied,
# from either side, is never applied over it.
module IncidentAction::IssueLink
  extend ActiveSupport::Concern

  ISSUE_CREATING = "creating".freeze
  ISSUE_AWAITING_APPROVAL = "awaiting_approval".freeze
  ISSUE_FAILED = "failed".freeze
  ISSUE_DECLINED = "declined".freeze
  ISSUE_LINKED = "linked".freeze
  ISSUE_GONE = "gone".freeze
  ISSUE_SYNC_STATES = [ ISSUE_CREATING, ISSUE_AWAITING_APPROVAL, ISSUE_FAILED, ISSUE_DECLINED, ISSUE_LINKED, ISSUE_GONE ].freeze
  # Where an issue was asked for and is not there, which asking again retries.
  ISSUE_MISSING = [ ISSUE_FAILED, ISSUE_DECLINED ].freeze

  # The fields kept in step, each with the column holding its last change.
  SYNCED_AT = {
    Integrations::Issues::FIELD_TITLE => :issue_title_synced_at,
    Integrations::Issues::FIELD_STATE => :issue_status_synced_at,
    Integrations::Issues::FIELD_ASSIGNEE => :issue_assignee_synced_at
  }.freeze

  ISSUE_UPDATE_ACTION_KEY = Ability::Action.system_key(Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE)

  # Raised inside a change that lost to a newer one, so its record is rolled back with it.
  class Superseded < StandardError; end

  included do
    belongs_to :issue_integration, class_name: "Integration", optional: true
    validates :issue_sync_state, inclusion: { in: ISSUE_SYNC_STATES }, allow_nil: true
    scope :linked_to_issue, ->(integration, keys) { active.where(issue_integration: integration, external_key: keys) }
  end

  def issue_linked? = external_url.present? && issue_sync_state != ISSUE_GONE

  # Whether changes to this item reach its issue and back. They do while it is linked to the workspace's tracker and that
  # connection is on.
  def issue_syncs?
    issue_linked? && issue_integration_id.present? && issue_integration_id == workspace.issue_sync_connection&.id
  end

  # Why nobody can ask for an issue for this item now, or nil when they can.
  def issue_request_blocked_reason
    return "This item already has an issue." if external_url.present?
    return "Firefight is opening its issue now." if issue_sync_state == ISSUE_CREATING
    return "Its issue is waiting for approval." if issue_sync_state == ISSUE_AWAITING_APPROVAL
    return "Choose an issue tracker under Settings, Workspace to open issues." if workspace.issue_tracker.blank? || workspace.issue_creation_never?

    workspace.issue_creation_blocked_reason
  end

  # Whether the dashboard and the Slack message offer to open an issue. Not while issues are never opened, not for work
  # that is done, and not once it has one or is getting one. A reason why it cannot be opened yet is shown when the
  # control is used rather than hiding it.
  def issue_request_offered?
    external_url.blank? && !done? && workspace.issue_tracker.present? && !workspace.issue_creation_never? &&
      [ ISSUE_CREATING, ISSUE_AWAITING_APPROVAL ].exclude?(issue_sync_state)
  end

  def issue_missing? = ISSUE_MISSING.include?(issue_sync_state)

  # What a person reads about the item's issue while it is not there or not kept in step, or nil.
  def issue_status_text
    return "Firefight is opening its issue." if issue_sync_state == ISSUE_CREATING

    issue_sync_note
  end

  # Asks the gateway whether Firefight's issue sync may make one call to the tracker for this item, and ledgers it with
  # the person whose change it was. Sync holds only the grants it was given, never that person's reach. The caller makes
  # the call and finalizes what this returns.
  def authorize_issue_call!(tool, by:, arguments:, approval_id: nil)
    AbilityGateway.authorize!(
      principal: SystemAgent.issue_sync, action_key: tool.action_key, workspace: workspace, scope: {}, params: arguments,
      context: { source: AbilityGateway::SOURCE_ISSUE_SYNC, approval_id: approval_id, incident_id: incident_id,
                 triggered_by_label: issue_change_label(by) }.compact
    )
  end

  # Whose change a call to the tracker carries, as the activity log shows it.
  def issue_change_label(by)
    item = "the #{action_type == IncidentAction::ACTION_TYPE_FOLLOWUP ? 'follow-up' : 'action'} on #{incident.identifier}"
    by ? "#{by.actor_display_name}, on #{item}" : item.upcase_first
  end

  # Records in the activity log a change the tracker made here, under Firefight's issue sync, since no person in
  # Firefight made it. params says what changed and never carries the tracker's payload.
  def record_issue_change!(params)
    action = Ability::Action.lookup(ISSUE_UPDATE_ACTION_KEY, workspace)
    AbilityGateway.record!(
      decision: Ability::Invocation::DECISION_ALLOW, completed_at: Time.current, principal: SystemAgent.issue_sync, action: action,
      action_key: ISSUE_UPDATE_ACTION_KEY, workspace: workspace, scope: {},
      params: params.merge("incident" => incident.identifier, "action_item" => id),
      context: { source: AbilityGateway::SOURCE_ISSUE_SYNC, incident_id: incident_id, triggered_by_label: issue_integration&.name }
    )
  end

  # Moves the issue state on only from where it was, so two workers never open one issue twice. False when it had moved.
  def move_issue!(from:, to:, **columns)
    won = self.class.where(id: id).where(issue_sync_state: Array(from)).update_all(issue_sync_state: to, updated_at: Time.current, **columns)
    reload
    won == 1
  end

  # Marks field as changed at at, only when nothing later was, so an older change from either side never wins. False
  # when a later change already had.
  # With from_status, only while the item is still in that status.
  def claim_issue_field!(field, at, from_status: nil, **columns)
    column = SYNCED_AT.fetch(field)
    scope = self.class.where(id: id).where("#{column} IS NULL OR #{column} < ?", at)
    scope = scope.where(status: from_status) if from_status
    scope.update_all(column => at, updated_at: Time.current, **columns) == 1
  end

  def issue_note!(note)
    update_columns(issue_sync_note: note&.truncate(1000), updated_at: Time.current)
  end

  private

  def workspace = incident.workspace
end
