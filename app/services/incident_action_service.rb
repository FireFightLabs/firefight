class IncidentActionService
  def initialize(workspace)
    @workspace = workspace
  end

  def create_action(incident:, created_by:, action_type:, description:, assignee: nil, platform_data: {})
    action = incident.incident_actions.create!(
      created_by: created_by,
      action_type: action_type,
      description: description,
      assignee: assignee,
      status: IncidentAction::STATUS_OPEN,
      platform_data: platform_data
    )

    action_update = IncidentActionUpdate.create!(
      incident_action: action,
      action_update_type: IncidentActionUpdate::CREATED,
      action_type: action_type,
      actor: created_by
    )

    incident.incident_events.create!(
      event_type: IncidentEvent::ACTION_CREATED,
      user: created_by,
      eventable: action_update
    )

    adapter = WorkspaceAdapter.for(@workspace)
    result = adapter.post_action_message(channel_id: incident.channel_id, action: action)
    action.update!(slack_message_ts: result[:message_ts])

    action
  end

  def pick_up_action(action:, picked_up_by:)
    action.update!(assignee: picked_up_by, status: IncidentAction::STATUS_IN_PROGRESS)

    action_update = IncidentActionUpdate.create!(
      incident_action: action,
      action_update_type: IncidentActionUpdate::PICKED_UP,
      action_type: action.action_type,
      actor: picked_up_by
    )

    action.incident.incident_events.create!(
      event_type: IncidentEvent::ACTION_PICKED_UP,
      user: picked_up_by,
      eventable: action_update
    )

    update_action_message(action, Slack::IncidentMessageBuilder.action_picked_up_blocks(action))
  end

  def complete_action(action:, completed_by:)
    action.update!(status: IncidentAction::STATUS_DONE)

    action_update = IncidentActionUpdate.create!(
      incident_action: action,
      action_update_type: IncidentActionUpdate::COMPLETED,
      action_type: action.action_type,
      actor: completed_by
    )

    action.incident.incident_events.create!(
      event_type: IncidentEvent::ACTION_COMPLETED,
      user: completed_by,
      eventable: action_update
    )

    update_action_message(action, Slack::IncidentMessageBuilder.action_completed_blocks(action))
  end

  private

  def update_action_message(action, blocks)
    return unless action.slack_message_ts

    adapter = WorkspaceAdapter.for(@workspace)
    adapter.update_action_message(
      channel_id: action.incident.channel_id,
      ts: action.slack_message_ts,
      action: action,
      blocks: blocks
    )
  end
end
