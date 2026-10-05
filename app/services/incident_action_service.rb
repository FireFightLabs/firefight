class IncidentActionService
  def initialize(workspace)
    @workspace = workspace
  end

  def create_action(incident:, created_by:, action_type:, description:, assignee: nil, platform_data: {}, runbook_step: nil,
                    external_key: nil, external_url: nil, issue_integration: nil)
    incident.refuse_action_item!(action_type)

    action = incident.incident_actions.create!(
      created_by: created_by,
      action_type: action_type,
      description: description,
      assignee: assignee,
      status: assignee ? IncidentAction::STATUS_IN_PROGRESS : IncidentAction::STATUS_OPEN,
      runbook_step: runbook_step,
      platform_data: platform_data,
      external_key: external_key,
      external_url: external_url,
      issue_integration: external_url && issue_integration,
      issue_sync_state: external_url && issue_integration ? IncidentAction::ISSUE_LINKED : nil
    )

    action.record_change!(IncidentEvent::ACTION_CREATED, by: created_by)

    # A step's row in the runbook message is its message, so it gets no card.
    unless action.from_runbook_step?
      result = @workspace.adapter.post_action_message(channel_id: incident.channel_id, action: action)
      action.update!(message_ts: result[:message_id])
    end

    refresh_runbook_message(action)
    IssueSyncService.new(@workspace).created(action, by: created_by)
    action
  end

  # A step somebody already touched is the item behind it, so claiming it is an ordinary claim.
  def assign_step(incident:, runbook_step:, assignee:, assigned_by:)
    existing = incident.incident_actions.active.find_by(runbook_step: runbook_step)
    return assign_action(action: existing, assignee: assignee, assigned_by: assigned_by) if existing

    action = create_action(
      incident: incident,
      created_by: assigned_by,
      action_type: IncidentAction::ACTION_TYPE_ACTION,
      description: runbook_step.title,
      assignee: assignee,
      runbook_step: runbook_step
    )
    announce_handover(action, assigned_by)
    action
  rescue ActiveRecord::RecordNotUnique
    incident.incident_actions.active.find_by(runbook_step: runbook_step)
  end

  # Claiming and handing over differ only in who ends up holding the work, so
  # callers do not have to pick. Returns the item either way.
  def assign_action(action:, assignee:, assigned_by:)
    if assignee == assigned_by && action.claimable?
      pick_up_action(action: action, picked_up_by: assigned_by)
    else
      reassign_action(action: action, assignee: assignee, reassigned_by: assigned_by)
    end

    action.reload
  end

  def pick_up_action(action:, picked_up_by:)
    action.record_change!(IncidentEvent::ACTION_PICKED_UP, by: picked_up_by) do
      action.update!(assignee: picked_up_by, status: IncidentAction::STATUS_IN_PROGRESS)
    end

    update_action_message(action, :picked_up)
    refresh_runbook_message(action)
    IssueSyncService.new(@workspace).changed(action, [ ISSUE_ASSIGNEE, ISSUE_STATE ], by: picked_up_by)
  end

  def reassign_action(action:, assignee:, reassigned_by:)
    return if action.done? || action.assignee_id == assignee.id

    action.record_change!(IncidentEvent::ACTION_REASSIGNED, by: reassigned_by) do
      action.update!(assignee: assignee, status: IncidentAction::STATUS_IN_PROGRESS)
    end

    update_action_message(action, :picked_up)
    announce_handover(action, reassigned_by)
    refresh_runbook_message(action)
    IssueSyncService.new(@workspace).changed(action, [ ISSUE_ASSIGNEE, ISSUE_STATE ], by: reassigned_by)
  end

  # tracked is false when the issue was closed first, so closing it again is not sent back to the tracker.
  def complete_action(action:, completed_by:, tracked: true)
    action.record_change!(IncidentEvent::ACTION_COMPLETED, by: completed_by) do
      action.update!(status: IncidentAction::STATUS_DONE)
    end

    update_action_message(action, :completed)
    refresh_runbook_message(action)
    announce_completion(action, completed_by)
    IssueSyncService.new(@workspace).changed(action, [ ISSUE_STATE ], by: completed_by) if tracked
  end

  # A change the item's issue made in its tracker, applied only when nothing newer changed the field from either side
  # and, with from_status, only while the item is still in that status, in one guarded statement so two deliveries
  # never both land. Answers whether it was applied. It is never sent back to the tracker.
  def apply_issue_change(action:, field:, at:, event_type:, by:, from_status: nil, **columns)
    IncidentAction.transaction do
      action.record_change!(event_type, by: by) do
        raise IncidentAction::Superseded unless action.claim_issue_field!(field, at, from_status: from_status, **columns)
      end
    end
    issue_change_made(action, event_type, by)
    true
  rescue IncidentAction::Superseded
    action.reload
    false
  end

  ISSUE_STATE = Integrations::Issues::FIELD_STATE
  ISSUE_ASSIGNEE = Integrations::Issues::FIELD_ASSIGNEE

  private

  # The channel sees a change from the tracker as it would one made here: the item's message redrawn, and a completion
  # or a handover announced.
  def issue_change_made(action, event_type, by)
    adapter = @workspace.adapter
    adapter.refresh_action_message(channel_id: action.incident.channel_id, message_id: action.message_ts, action: action) if action.message_ts
    refresh_runbook_message(action)
    case event_type
    when IncidentEvent::ACTION_COMPLETED then announce_completion(action, by)
    when IncidentEvent::ACTION_REASSIGNED then announce_handover(action, by)
    end
  rescue AdapterError => error
    Rails.logger.warn({ event: "incident_action.issue_change_message_failed", action_id: action.id, error: error.message }.to_json)
  end

  # Editing a message notifies nobody, so a handover posts while taking it yourself does not.
  # An item has exactly one message carrying its controls, a handover points at it rather than posting a second set.
  def announce_handover(action, actor)
    return if action.assignee == actor
    return adopt_handover_as_message(action, actor) if action.message_ts.blank?

    @workspace.adapter.post_action_handover_notice(
      channel_id: action.incident.channel_id,
      action: action,
      reassigned_by: actor,
      link: origin_link(action)
    )
  end

  def adopt_handover_as_message(action, actor)
    result = @workspace.adapter.post_action_handed_over(
      channel_id: action.incident.channel_id,
      action: action,
      reassigned_by: actor
    )
    action.update!(message_ts: result[:message_id])
  end

  # Finishing work by only editing a message nobody is looking at is invisible.
  def announce_completion(action, completed_by)
    @workspace.adapter.post_action_completed(
      channel_id: action.incident.channel_id,
      action: action,
      completed_by: completed_by,
      link: origin_link(action)
    )
  end

  # A link is a url and a label together or it is nothing.
  def origin_link(action)
    reference = action.origin_reference
    url = reference.url.presence || permalink(action.incident.channel_id, reference.message_ts)
    return nil if url.blank?

    reference.with(url: url)
  end

  def permalink(channel_id, message_ts)
    return nil if message_ts.blank?

    @workspace.adapter.get_message_permalink(channel_id: channel_id, message_id: message_ts)[:permalink]
  rescue AdapterError => e
    Rails.logger.warn({ event: "incident_action.permalink_failed", error: e.message })
    nil
  end

  def refresh_runbook_message(action)
    return unless action.from_runbook_step?

    RunbookAttachmentService.new(@workspace).refresh_message_for_step(action.incident, action.runbook_step)
  end

  def update_action_message(action, update_type)
    return unless action.message_ts

    adapter = @workspace.adapter
    case update_type
    when :picked_up
      adapter.update_action_picked_up(
        channel_id: action.incident.channel_id,
        message_id: action.message_ts,
        action: action
      )
    when :completed
      adapter.update_action_completed(
        channel_id: action.incident.channel_id,
        message_id: action.message_ts,
        action: action
      )
    end
  end
end
