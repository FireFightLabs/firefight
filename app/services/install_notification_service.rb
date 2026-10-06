# Failures are logged, never shown to the installer.
class InstallNotificationService
  DeliveryFailed = TeamWebhook::DeliveryFailed

  def self.configured? = TeamWebhook.configured?

  def notify(workspace, installer)
    TeamWebhook.post!(payload(workspace, installer))
    Rails.logger.info({ event: "install_notification.sent", workspace_id: workspace.id })
  end

  private

  def payload(workspace, installer)
    {
      text: "New install: #{workspace.name} (#{workspace.platform} #{workspace.platform_id}) by #{installer.display_name} (#{installer.email})",
      workspace_name: workspace.name,
      platform: workspace.platform,
      platform_id: workspace.platform_id,
      installer_name: installer.display_name,
      installer_email: installer.email,
      installed_at: workspace.installed_at.utc.iso8601
    }
  end
end
