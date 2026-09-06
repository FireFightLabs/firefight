# POSTs a JSON note about a new install to a webhook URL. A Slack incoming
# webhook renders the text field. Failures are logged, never shown to the
# installer.
class InstallNotificationService
  class DeliveryFailed < StandardError; end

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 5

  def self.configured?
    Rails.configuration.x.install_notification_webhook_url.present?
  end

  def notify(workspace, installer)
    uri = URI.parse(Rails.configuration.x.install_notification_webhook_url)
    request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
    request.body = payload(workspace, installer).to_json

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                               open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
      http.request(request)
    end

    raise DeliveryFailed, "#{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)

    Rails.logger.info({ event: "install_notification.sent", workspace_id: workspace.id })
  rescue SocketError, Timeout::Error, OpenSSL::SSL::SSLError, Errno::ECONNREFUSED, Errno::ECONNRESET => e
    raise DeliveryFailed, "#{e.class.name}: #{e.message}"
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
