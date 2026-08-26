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

  # A step somebody has already touched is the item behind it, so claiming it
  # is the same operation as claiming any other piece of work.
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

  # Taking a piece of work and handing it over differ only in who ends up
  # holding it, so a caller that knows the assignee does not also have to
  # decide which of the two this is. Returns the item either way, since the
  # two verbs below return whatever their last message call did.
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
    announce_completion(action, completed_by)
  end

  private

  # Editing a message notifies nobody, so giving work to someone else has to
  # post. Taking it yourself does not, because you already know.
  #
  # An item holds exactly one message, the one carrying its controls. A handover
  # either becomes that message or points at it, never posts a second set of
  # controls that nothing would keep up to date.
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

  # Work spread across an incident is invisible if finishing it only edits a
  # message nobody is looking at.
  def announce_completion(action, completed_by)
    @workspace.adapter.post_action_completed(
      channel_id: action.incident.channel_id,
      action: action,
      completed_by: completed_by,
      link: origin_link(action)
    )
  end

  # A link is a url and a label together or it is nothing, so it resolves to one
  # value rather than two that callers have to keep in step.
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
