# Firefight's own notes to the people running it, posted to the incoming webhook INSTALL_NOTIFICATION_WEBHOOK_URL
# names. A Slack incoming webhook renders the text field. Unset sends nothing.
class TeamWebhook
  class DeliveryFailed < StandardError; end

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 5

  def self.configured? = url.present?

  def self.url = Rails.configuration.x.install_notification_webhook_url

  # mention names the person the note is for, by their id in the chat the webhook posts to.
  def self.post!(payload, mention: nil)
    payload = payload.merge(text: "<@#{mention}> #{payload[:text]}") if mention.present? && payload[:text]
    uri = URI.parse(url)
    request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
    request.body = payload.to_json

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                               open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
      http.request(request)
    end

    raise DeliveryFailed, "#{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)
  rescue SocketError, Timeout::Error, OpenSSL::SSL::SSLError, Errno::ECONNREFUSED, Errno::ECONNRESET => e
    raise DeliveryFailed, "#{e.class.name}: #{e.message}"
  end
end
