class IncidentActionService
  def initialize(workspace)
    @workspace = workspace
  end

  def create_action(incident:, created_by:, action_type:, description:, assignee: nil, platform_data: {}, runbook_step: nil)
    action = incident.incident_actions.create!(
      created_by: created_by,
      action_type: action_type,
      description: description,
      assignee: assignee,
      status: assignee ? IncidentAction::STATUS_IN_PROGRESS : IncidentAction::STATUS_OPEN,
      runbook_step: runbook_step,
      platform_data: platform_data
    )

    action.record_change!(IncidentEvent::ACTION_CREATED, by: created_by)

    # A step's row in the runbook message is its message, so it gets no card.
    unless action.from_runbook_step?
      result = @workspace.adapter.post_action_message(channel_id: incident.channel_id, action: action)
      action.update!(message_ts: result[:message_id])
    end

    refresh_runbook_message(action)
    action
  end

  # Taking a step and handing one out are the same operation, differing only in
  # who ends up holding it.
  def assign_step(incident:, runbook_step:, assignee:, assigned_by:)
    existing = incident.incident_actions.active.find_by(runbook_step: runbook_step)
    return reassign_action(action: existing, assignee: assignee, reassigned_by: assigned_by) if existing

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

  def pick_up_action(action:, picked_up_by:)
    action.record_change!(IncidentEvent::ACTION_PICKED_UP, by: picked_up_by) do
      action.update!(assignee: picked_up_by, status: IncidentAction::STATUS_IN_PROGRESS)
    end

    update_action_message(action, :picked_up)
    refresh_runbook_message(action)
  end

  def reassign_action(action:, assignee:, reassigned_by:)
    return if action.done? || action.assignee_id == assignee.id

    action.record_change!(IncidentEvent::ACTION_REASSIGNED, by: reassigned_by) do
      action.update!(assignee: assignee, status: IncidentAction::STATUS_IN_PROGRESS)
    end

    update_action_message(action, :picked_up)
    announce_handover(action, reassigned_by)
    refresh_runbook_message(action)
  end

  def complete_action(action:, completed_by:)
    action.record_change!(IncidentEvent::ACTION_COMPLETED, by: completed_by) do
      action.update!(status: IncidentAction::STATUS_DONE)
    end

    update_action_message(action, :completed)
    refresh_runbook_message(action)
  end

  private

  # Editing a message notifies nobody, so giving work to someone else has to
  # post. Taking it yourself does not, because you already know.
  def announce_handover(action, actor)
    return if action.assignee == actor

    @workspace.adapter.post_action_reassigned(
      channel_id: action.incident.channel_id,
      action: action,
      reassigned_by: actor
    )
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
