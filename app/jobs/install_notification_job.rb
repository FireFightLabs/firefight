# One retry, then log and drop. The install never waits on this.
class InstallNotificationJob < ApplicationJob
  queue_as :default

  retry_on InstallNotificationService::DeliveryFailed, wait: 30.seconds, attempts: 2 do |job, error|
    workspace_id, = job.arguments
    Rails.logger.warn({ event: "install_notification.failed", workspace_id: workspace_id, error: error.message })
  end
  discard_on ActiveRecord::RecordNotFound

  def perform(workspace_id, installer_membership_id)
    workspace = Workspace.find(workspace_id)
    installer = workspace.workspace_memberships.find(installer_membership_id)
    InstallNotificationService.new.notify(workspace, installer)
  end
end
