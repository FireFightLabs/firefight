# Every message posted is remembered on the approval so the decision can be
# reflected in place. Workspaces without a channel still resolve approvals from the dashboard.
class ApprovalNotificationService
  def self.post!(approval)
    workspace = approval.workspace
    adapter = WorkspaceAdapter.for(workspace)

    if approval.notify_channel? && workspace.incidents_channel_id.present?
      deliver(approval) { adapter.post_approval_request(approval: approval, channel_id: workspace.incidents_channel_id) }
    end

    asked = approval.notify_dm? ? approval.human_approvers : []
    # Nobody working the incident can decide, so whoever is on call for it is asked directly too.
    (asked | approval.on_call_to_ask).each { |member| ask_directly(approval, member, adapter) }
  end

  # Someone just escalated to is on call for the incident from now on, so each request waiting there that they may
  # decide as whoever is on call reaches them too, by the same rule as when it was made, and never twice.
  def self.ask_on_call!(incident, member)
    adapter = WorkspaceAdapter.for(incident.workspace)
    incident.workspace.ability_approvals.pending.where(incident_id: incident.id, on_call_may_approve: true).find_each do |approval|
      ask_directly(approval, member, adapter) if approval.on_call_to_ask.include?(member)
    end
  end

  # Each member is asked directly once per request, whichever way they came to be asked.
  def self.ask_directly(approval, member, adapter)
    return if member.platform_user_id.blank? || !approval.claim_ask!(member)

    deliver(approval) { adapter.post_approval_request_to_user(approval: approval, user_id: member.platform_user_id) }
  end
  private_class_method :ask_directly

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
