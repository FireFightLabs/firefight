class Webhooks::DeliveryService
  class ResponseTooLarge < StandardError; end

  USER_AGENT = "Firefight-Webhooks/1.0"
  ENDPOINT_TIMEOUT = 7.seconds
  MAX_RESPONSE_SIZE = 100.kilobytes

  def self.deliver(webhook_delivery)
    new(webhook_delivery).deliver
  end

  def initialize(webhook_delivery)
    @delivery = webhook_delivery
    @webhook = webhook_delivery.webhook
  end

  def deliver
    @delivery.in_progress!

    payload = Webhooks::PayloadRenderer.render(
      @delivery.incident_event,
      delivery_id: @delivery.id
    )

    resolved_ip = Webhooks::SsrfProtector.resolve_public_ip(uri.host)
    if resolved_ip.nil?
      record_error("private_uri")
      return
    end

    request_headers = build_headers(payload)
    @delivery.update!(request_headers: request_headers, request_body: JSON.parse(payload))

    response = perform_request(payload, request_headers, resolved_ip)
    @delivery.update!(
      state: :completed,
      response_code: response[:code],
      error_message: response[:error],
      delivered_at: Time.current
    )

    @webhook.webhook_delinquency_tracker&.record_delivery(@delivery)
  rescue ResponseTooLarge
    record_error("response_too_large")
    @webhook.webhook_delinquency_tracker&.record_delivery(@delivery)
  rescue Resolv::ResolvTimeout, Resolv::ResolvError, SocketError
    record_error("dns_lookup_failed")
    @webhook.webhook_delinquency_tracker&.record_delivery(@delivery)
  rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ETIMEDOUT
    record_error("connection_timeout")
    @webhook.webhook_delinquency_tracker&.record_delivery(@delivery)
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ECONNRESET
    record_error("destination_unreachable")
    @webhook.webhook_delinquency_tracker&.record_delivery(@delivery)
  rescue OpenSSL::SSL::SSLError
    record_error("failed_tls")
    @webhook.webhook_delinquency_tracker&.record_delivery(@delivery)
  end

  private

  def uri
    @uri ||= URI(@webhook.url)
  end

  def build_headers(payload)
    {
      "User-Agent" => USER_AGENT,
      "Content-Type" => "application/json",
      "X-Webhook-Signature" => signature(payload),
      "X-Webhook-Event" => @delivery.event_type,
      "X-Webhook-Delivery" => @delivery.id
    }
  end

  def signature(payload)
    OpenSSL::HMAC.hexdigest("SHA256", @webhook.signing_secret, payload)
  end

  def perform_request(payload, headers, resolved_ip)
    http = Net::HTTP.new(uri.host, uri.port).tap do |h|
      h.ipaddr = resolved_ip
      h.use_ssl = (uri.scheme == "https")
      h.open_timeout = ENDPOINT_TIMEOUT
      h.read_timeout = ENDPOINT_TIMEOUT
    end

    request = Net::HTTP::Post.new(uri, headers)
    request.body = payload

    response = http.request(request) do |net_response|
      stream_body_with_limit(net_response)
    end

    { code: response.code.to_i }
  end

  def stream_body_with_limit(response)
    bytes_read = 0
    response.read_body do |chunk|
      bytes_read += chunk.bytesize
      raise ResponseTooLarge if bytes_read > MAX_RESPONSE_SIZE
    end
  end

  def record_error(message)
    @delivery.update!(state: :errored, error_message: message)
  end
end
