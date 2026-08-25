# Surfaces a pending approval wherever the rule said to ask, the incidents
# channel, a direct message to each approver, or both. Every message posted is
# remembered on the approval so the decision can be reflected in place.
# Workspaces without a channel still resolve approvals from the dashboard.
class ApprovalNotificationService
  def self.post!(approval)
    workspace = approval.workspace
    adapter = WorkspaceAdapter.for(workspace)

    if approval.notify_channel? && workspace.incidents_channel_id.present?
      deliver(approval) { adapter.post_approval_request(approval: approval, channel_id: workspace.incidents_channel_id) }
    end

    if approval.notify_dm?
      approval.human_approvers.each do |approver|
        deliver(approval) { adapter.post_approval_request_to_user(approval: approval, user_id: approver.platform_user_id) }
      end
    end
  end

  def self.mark_resolved!(approval)
    adapter = WorkspaceAdapter.for(approval.workspace)
    approval.notifications.each do |notification|
      adapter.mark_approval_resolved(
        approval: approval, channel_id: notification["channel_id"], message_id: notification["message_id"]
      )
    rescue AdapterError => e
      Rails.logger.warn({ event: "approval.resolution_update_failed", approval_id: approval.id, error: e.class.name }.to_json)
    end
  end

  def self.deliver(approval)
    result = yield
    approval.add_notification!(channel_id: result[:channel_id], message_id: result[:message_id])
  rescue AdapterError => e
    Rails.logger.warn({ event: "approval.notification_failed", approval_id: approval.id, error: e.class.name }.to_json)
  end
  private_class_method :deliver
end
