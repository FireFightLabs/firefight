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

    action.create_initial_update!(actor: created_by)

    adapter = WorkspaceAdapter.for(@workspace)
    result = adapter.post_action_message(channel_id: incident.channel_id, action: action)
    action.update!(message_ts: result[:message_ts])

    action
  end

  def pick_up_action(action:, picked_up_by:)
    action.record_change!(IncidentEvent::ACTION_PICKED_UP, actor: picked_up_by) do
      action.update!(assignee: picked_up_by, status: IncidentAction::STATUS_IN_PROGRESS)
    end

    update_action_message(action, :picked_up)
  end

  def complete_action(action:, completed_by:)
    action.record_change!(IncidentEvent::ACTION_COMPLETED, actor: completed_by) do
      action.update!(status: IncidentAction::STATUS_DONE)
    end

    update_action_message(action, :completed)
  end

  private

  def update_action_message(action, update_type)
    return unless action.message_ts

    adapter = WorkspaceAdapter.for(@workspace)
    case update_type
    when :picked_up
      adapter.update_action_picked_up(
        channel_id: action.incident.channel_id,
        ts: action.message_ts,
        action: action
      )
    when :completed
      adapter.update_action_completed(
        channel_id: action.incident.channel_id,
        ts: action.message_ts,
        action: action
      )
    end
  end
end
