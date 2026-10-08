# One retry, then log and drop. Signing up and connecting never wait on this.
class SignupNotificationJob < ApplicationJob
  queue_as :default

  retry_on SignupNotificationService::DeliveryFailed, wait: 30.seconds, attempts: 2 do |job, error|
    event, workspace_id, = job.arguments
    Rails.logger.warn({ event: "signup_notification.failed", notification: event, workspace_id: workspace_id, error: error.message })
  end
  discard_on ActiveRecord::RecordNotFound

  def perform(event, workspace_id, membership_id, sign_up_method = nil)
    workspace = Workspace.find(workspace_id)
    member = workspace.workspace_memberships.find(membership_id)
    SignupNotificationService.new.notify(event, workspace, member, sign_up_method: sign_up_method)
  end
end
