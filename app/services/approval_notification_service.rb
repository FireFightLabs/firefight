# Surfaces a pending approval to the workspace's incidents channel with
# approve/deny buttons and remembers the message so the decision can be
# reflected in place. Workspaces without a configured channel still resolve
# approvals from the dashboard endpoints.
class ApprovalNotificationService
  def self.post!(approval)
    workspace = approval.workspace
    channel_id = workspace.incidents_channel_id
    return if channel_id.blank?

    result = WorkspaceAdapter.for(workspace).post_approval_request(approval: approval, channel_id: channel_id)
    approval.update!(slack_channel_id: result[:channel_id], slack_message_ts: result[:message_id])
  rescue AdapterError => e
    Rails.logger.warn({ event: "approval.notification_failed", approval_id: approval.id, error: e.class.name }.to_json)
  end

  def self.mark_resolved!(approval)
    return if approval.slack_channel_id.blank? || approval.slack_message_ts.blank?

    WorkspaceAdapter.for(approval.workspace).mark_approval_resolved(
      approval: approval, channel_id: approval.slack_channel_id, message_id: approval.slack_message_ts
    )
  rescue AdapterError => e
    Rails.logger.warn({ event: "approval.resolution_update_failed", approval_id: approval.id, error: e.class.name }.to_json)
  end
end
