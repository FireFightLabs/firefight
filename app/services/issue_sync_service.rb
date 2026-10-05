# Keeps an incident's items and their issues in the workspace's tracker in step (Workspace::IssueSync). A change made in
# Firefight goes to the issue through the gateway as whoever made it, in a job, since the tracker is another system. A
# change the tracker sends back is applied to the item as Firefight's issue sync and never sent back, so nothing echoes.
# Each field keeps the time of its last change from either side (IncidentAction::IssueLink), so an older change never
# lands over a newer one, whichever order they arrive in.
class IssueSyncService
  OPEN_ISSUE = "open".freeze
  PUSH = "push".freeze
  OPERATIONS = [ OPEN_ISSUE, PUSH ].freeze

  Issues = Integrations::Issues

  def initialize(workspace)
    @workspace = workspace
  end

  # A new item gets an issue when the workspace opens one for every item of its kind.
  def created(action, by:)
    return if action.external_url.present? || !@workspace.creates_issue_for?(action.action_type)

    open_issue(action, by: by)
  end

  # Someone asked for the item's issue, or for it again after it failed. Answers why it cannot be asked for, or nil.
  def request(action, by:)
    reason = action.issue_request_blocked_reason
    return reason if reason

    open_issue(action, by: by)
    nil
  end

  # A change someone made in Firefight to fields of a linked item, which its issue takes.
  def changed(action, fields, by:)
    return unless action.issue_syncs?

    now = Time.current
    claimed = fields.select { |field| action.claim_issue_field!(field, now) }
    IssueSyncJob.perform_later(operation: PUSH, action: action, principal: by, fields: claimed) if claimed.any?
  end

  def perform(operation, action, principal, fields: [], approval_id: nil)
    operation == OPEN_ISSUE ? open_now(action, principal, approval_id) : push_now(action, principal, fields, approval_id)
  end

  # A delivery from the tracker's webhook that its signature proved, applied in a job.
  def receive(event)
    IssueChangeJob.perform_later(workspace: @workspace, event: event.to_job)
  end

  # What the tracker changed, applied to every item linked to that issue on the workspace's tracker.
  def apply(event)
    integration = @workspace.issue_sync_connection
    return unless integration

    IncidentAction.in_workspace(@workspace).linked_to_issue(integration, event.keys).includes(:incident).find_each do |action|
      apply_to(action, event)
    end
  end

  # An approver decided on a call parked for an item's issue. Approved, it runs again with the approval. Declined, the
  # item says so.
  def decided(approval, payload)
    action = IncidentAction.in_workspace(@workspace).find_by(id: payload["action_id"])
    return unless action

    if approval.approved?
      IssueSyncJob.perform_later(operation: payload["operation"], action: action, principal: approval.principal,
                                 fields: Array(payload["fields"]), approval_id: approval.id)
    elsif payload["operation"] == OPEN_ISSUE
      declined = "#{approver(approval)} declined opening its issue."
      refresh(action) if action.move_issue!(from: IncidentAction::ISSUE_AWAITING_APPROVAL, to: IncidentAction::ISSUE_DECLINED, issue_sync_note: declined)
    else
      action.issue_note!("#{approver(approval)} declined updating #{action.external_key}, so it was left as it was.")
    end
  end

  private

  def open_issue(action, by:)
    integration = @workspace.issue_tracker_connection
    reason = @workspace.issue_creation_blocked_reason
    if reason || integration.nil?
      failed = action.move_issue!(from: [ nil, *IncidentAction::ISSUE_MISSING ], to: IncidentAction::ISSUE_FAILED,
                                  issue_sync_note: reason || "Choose an issue tracker under Settings, Workspace to open issues.")
      refresh(action) if failed
      return
    end

    asked = action.move_issue!(from: [ nil, *IncidentAction::ISSUE_MISSING ], to: IncidentAction::ISSUE_CREATING, issue_sync_note: nil,
                               issue_integration_id: integration.id)
    return unless asked

    refresh(action)
    IssueSyncJob.perform_later(operation: OPEN_ISSUE, action: action, principal: by)
  end

  def open_now(action, principal, approval_id)
    waiting = [ IncidentAction::ISSUE_CREATING, IncidentAction::ISSUE_AWAITING_APPROVAL ]
    return unless waiting.include?(action.issue_sync_state) && action.external_url.blank?

    integration = action.issue_integration
    target = @workspace.issue_tracker_target
    outcome = session(action, integration, principal, approval_id).create(
      title: action.description, description: issue_description(action), target: target, assignee_email: email_of(action.assignee)
    )
    issue = outcome.issue
    now = Time.current
    linked = action.move_issue!(
      from: waiting, to: IncidentAction::ISSUE_LINKED, external_key: issue.key, external_url: issue.url, issue_approval_id: nil,
      issue_sync_note: notes_of(outcome, action), issue_title_synced_at: now, issue_status_synced_at: now, issue_assignee_synced_at: now
    )
    return unless linked

    refresh(action)
    catch_up(action, principal, outcome)
  rescue AbilityGateway::PendingApproval => pending
    park(action, pending.approval, OPEN_ISSUE, [], from: waiting, to: IncidentAction::ISSUE_AWAITING_APPROVAL,
         note: "Opening its issue in #{integration.name} is waiting for approval.")
  rescue AbilityGateway::Denied => denied
    fail_open(action, waiting, "#{principal.actor_display_name} may not use #{denied.action_key}, so its issue was not opened.")
  rescue Integrations::Error => error
    fail_open(action, waiting, error.message)
  end

  # What changed while the issue was being opened, such as the item picked up or finished, goes to it at once.
  def catch_up(action, principal, outcome)
    state = state_of(action)
    fields = []
    fields << Issues::FIELD_STATE if state != outcome.issue.state && state != Issues::STATE_OPEN
    fields << Issues::FIELD_TITLE if outcome.issue.title.present? && outcome.issue.title != action.description
    changed(action, fields, by: principal) if fields.any?
  end

  def push_now(action, principal, fields, approval_id)
    return unless action.issue_syncs?

    asked = {}
    asked[:title] = action.description if fields.include?(Issues::FIELD_TITLE)
    asked[:state] = state_of(action) if fields.include?(Issues::FIELD_STATE)
    notes = []
    if fields.include?(Issues::FIELD_ASSIGNEE)
      email = email_of(action.assignee)
      email ? asked[:assignee_email] = email : notes << unassignable(action)
    end
    return action.issue_note!(notes.compact.join(" ").presence) if asked.empty?

    outcome = session(action, action.issue_integration, principal, approval_id).update(key: action.external_key, target: @workspace.issue_tracker_target, **asked)
    return gone(action, Issues::GONE_DELETED, by: principal) if outcome.gone

    # Taken once the tracker has it, so the tracker's own report of this change is older and is never applied back.
    now = Time.current
    fields.each { |field| action.claim_issue_field!(field, now) }
    action.issue_note!([ *notes, *outcome.notes ].compact.join(" ").presence)
  rescue AbilityGateway::PendingApproval => pending
    park(action, pending.approval, PUSH, fields, note: "Updating #{action.external_key} in #{action.issue_integration.name} is waiting for approval.")
  rescue AbilityGateway::Denied => denied
    action.issue_note!("#{principal.actor_display_name} may not use #{denied.action_key}, so #{action.external_key} was not updated.")
  rescue Integrations::Error => error
    action.issue_note!(error.message)
  end

  def apply_to(action, event)
    return gone(action, event.gone, by: SystemAgent.issue_sync) if event.gone

    moved(action, event)
    by = SystemAgent.issue_sync
    service = IncidentActionService.new(@workspace)
    applied = []
    if event.changed?(Issues::FIELD_TITLE) && event.title.present? && event.title != action.description
      applied << "title" if service.apply_issue_change(action: action, field: Issues::FIELD_TITLE, at: event.at, by: by,
                                                       event_type: IncidentEvent::ACTION_RENAMED, description: event.title)
    end
    applied << "status" if event.changed?(Issues::FIELD_STATE) && apply_state(service, action.reload, event, by)
    applied << "assignee" if event.changed?(Issues::FIELD_ASSIGNEE) && apply_assignee(service, action.reload, event, by)
    action.record_issue_change!("issue" => action.external_key, "changed" => applied) if applied.any?
  end

  def apply_state(service, action, event, by)
    if event.state == Issues::STATE_DONE && !action.done?
      service.apply_issue_change(action: action, field: Issues::FIELD_STATE, at: event.at, by: by, from_status: action.status,
                                 event_type: IncidentEvent::ACTION_COMPLETED, status: IncidentAction::STATUS_DONE)
    elsif event.state && event.state != Issues::STATE_DONE && action.done?
      reopened = action.assigned? ? IncidentAction::STATUS_IN_PROGRESS : IncidentAction::STATUS_OPEN
      service.apply_issue_change(action: action, field: Issues::FIELD_STATE, at: event.at, by: by, from_status: IncidentAction::STATUS_DONE,
                                 event_type: IncidentEvent::ACTION_REOPENED, status: reopened)
    end
  end

  # A tracker account matches a member by email. One that matches nobody leaves the item's assignee alone and says so.
  def apply_assignee(service, action, event, by)
    if event.assignee_email.nil?
      return false unless action.assigned?

      status = action.done? ? action.status : IncidentAction::STATUS_OPEN
      return service.apply_issue_change(action: action, field: Issues::FIELD_ASSIGNEE, at: event.at, by: by, from_status: action.status,
                                        event_type: IncidentEvent::ACTION_UNASSIGNED, assignee_id: nil, assignee_type: nil, status: status)
    end

    member = @workspace.workspace_memberships.joins(:user).find_by(users: { email: event.assignee_email.downcase })
    unless member
      action.issue_note!("#{event.assignee_name.presence || event.assignee_email} has no Firefight account with the email " \
                         "#{event.assignee_email}, so this item's assignee was left as it was.")
      return false
    end
    return false if action.assignee == member

    status = action.done? ? action.status : IncidentAction::STATUS_IN_PROGRESS
    service.apply_issue_change(action: action, field: Issues::FIELD_ASSIGNEE, at: event.at, by: by, from_status: action.status,
                               event_type: IncidentEvent::ACTION_REASSIGNED, assignee_id: member.id, assignee_type: member.class.polymorphic_name,
                               status: status)
  end

  # An issue moved to another team or project keeps its item, under its new key.
  def moved(action, event)
    return if event.key == action.external_key

    action.update_columns(external_key: event.key, external_url: event.url.presence || action.external_url, updated_at: Time.current)
  end

  def gone(action, how, by:)
    note = "#{action.external_key} was #{how} in #{action.issue_integration&.name || 'the tracker'}, so this item is no longer kept in step with it."
    return unless action.move_issue!(from: IncidentAction::ISSUE_LINKED, to: IncidentAction::ISSUE_GONE, issue_sync_note: note)

    action.record_issue_change!("issue" => action.external_key, "changed" => [ how ]) if by.is_a?(SystemAgent)
    refresh(action)
  end

  def session(action, integration, principal, approval_id)
    raise Issues::Failed, "The connection that holds this item's issue was removed or switched off." unless integration&.operational?

    Issues.session(integration) do |tool, arguments, &run|
      authorization = action.authorize_issue_call!(tool, principal: principal, arguments: arguments, approval_id: approval_id)
      begin
        result = run.call
        authorization.answer_failed!(Integrations::Sentence.of(text_of(result))) if result.is_a?(Hash) && result["isError"]
        authorization.finalize_answered!
        result
      rescue StandardError => error
        authorization.finalize_error!(error)
        raise
      end
    end
  end

  def park(action, approval, operation, fields, note:, from: nil, to: nil)
    approval.update!(resume_payload: { kind: ApprovalResumption::KIND_ISSUE_SYNC, action_id: action.id, operation: operation, fields: fields })
    if from
      action.move_issue!(from: from, to: to, issue_approval_id: approval.id, issue_sync_note: note)
      refresh(action)
    else
      action.issue_note!(note)
    end
  end

  def fail_open(action, from, note)
    refresh(action) if action.move_issue!(from: from, to: IncidentAction::ISSUE_FAILED, issue_sync_note: note, issue_approval_id: nil)
  end

  def state_of(action)
    return Issues::STATE_DONE if action.done?

    action.assigned? ? Issues::STATE_STARTED : Issues::STATE_OPEN
  end

  def email_of(assignee) = assignee.is_a?(WorkspaceMembership) ? assignee.email.presence : nil

  def unassignable(action)
    return if action.assignee.nil?

    "#{action.assignee.actor_display_name} is not a person with an email, so the issue's assignee was left as it was."
  end

  def notes_of(outcome, action)
    [ unassignable_on_open(action), *outcome.notes ].compact.join(" ").presence
  end

  def unassignable_on_open(action) = action.assignee && email_of(action.assignee).nil? ? unassignable(action) : nil

  def issue_description(action)
    incident = action.incident
    link = incident_url(incident)
    kind = action.action_type == IncidentAction::ACTION_TYPE_FOLLOWUP ? "A follow-up" : "An action"
    [ "#{kind} from #{incident.identifier}, #{incident.name}, in Firefight.", link ].compact.join("\n\n")
  end

  def incident_url(incident)
    host = ENV["APP_HOST"].presence
    host && Rails.application.routes.url_helpers.incident_url(incident, host: host, protocol: ENV.fetch("APP_PROTOCOL", "https"))
  end

  def approver(approval) = approval.approver&.actor_display_name || "A workspace admin"

  def text_of(result) = Array(result["content"]).filter_map { |part| part["text"] }.join("\n")

  # The item's message in the incident channel shows its issue, so it is redrawn when that changes.
  def refresh(action)
    return if action.message_ts.blank?

    @workspace.adapter.refresh_action_message(channel_id: action.incident.channel_id, message_id: action.message_ts, action: action)
  rescue AdapterError => error
    Rails.logger.warn({ event: "issue_sync.message_refresh_failed", action_id: action.id, error: error.message }.to_json)
  end
end
