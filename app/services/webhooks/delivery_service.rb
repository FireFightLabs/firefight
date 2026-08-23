class Webhooks::DeliveryService
  class ResponseTooLarge < StandardError; end

  USER_AGENT          = "Firefight-Webhooks/1.0"
  ENDPOINT_TIMEOUT    = 7.seconds
  MAX_RESPONSE_SIZE   = 100.kilobytes
  PAYLOAD_VERSION     = "1"
  SIGNATURE_SCHEME    = "v1"

  def self.deliver(webhook_delivery)
    new(webhook_delivery).deliver
  end

  def initialize(webhook_delivery)
    @delivery = webhook_delivery
    @webhook  = webhook_delivery.webhook
  end

  def deliver
    @delivery.in_progress!
    @delivery.increment!(:attempts)

    payload = signed_payload
    resolved_ip = Webhooks::SsrfProtector.resolve_public_ip(uri.host)
    return record_error("private_uri") if resolved_ip.nil?

    timestamp = Time.current.utc.iso8601
    request_headers = build_headers(payload, timestamp)
    @delivery.update!(request_headers: request_headers, request_body: JSON.parse(payload))

    response = perform_request(payload, request_headers, resolved_ip)
    if response[:code].between?(200, 299)
      @delivery.update!(state: :succeeded, response_code: response[:code], delivered_at: Time.current)
    else
      @delivery.update!(state: :failed, response_code: response[:code], error_message: "http_#{response[:code]}")
    end

    record_outcome
  rescue ResponseTooLarge
    record_error("response_too_large")
  rescue Resolv::ResolvTimeout, Resolv::ResolvError, SocketError
    record_error("dns_lookup_failed")
  rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ETIMEDOUT
    record_error("connection_timeout")
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ECONNRESET
    record_error("destination_unreachable")
  rescue OpenSSL::SSL::SSLError
    record_error("failed_tls")
  end

  private

  # Renders the payload once and stores it on the delivery row. Subsequent
  # retries reuse the exact same bytes so the signature matches and the
  # consumer sees an immutable payload regardless of incident state drift.
  def signed_payload
    return @delivery.signed_payload if @delivery.signed_payload.present?

    payload = Webhooks::PayloadRenderer.render(@delivery.incident_event, delivery_id: @delivery.id)
    @delivery.update!(signed_payload: payload)
    payload
  end

  def uri
    @uri ||= URI(@webhook.url)
  end

  def build_headers(payload, timestamp)
    {
      "User-Agent"          => USER_AGENT,
      "Content-Type"        => "application/json",
      "X-Webhook-Version"   => PAYLOAD_VERSION,
      "X-Webhook-Event"     => @delivery.event_type,
      "X-Webhook-Delivery"  => @delivery.id,
      "X-Webhook-Attempt"   => @delivery.attempts.to_s,
      "X-Webhook-Timestamp" => timestamp,
      "X-Webhook-Signature" => "#{SIGNATURE_SCHEME}=#{signature(payload, timestamp)}"
    }
  end

  # Signing input is "<scheme>:<timestamp>:<body>". Consumers must verify
  # the timestamp is within their freshness window before HMAC-comparing.
  def signature(payload, timestamp)
    OpenSSL::HMAC.hexdigest("SHA256", @webhook.signing_secret, "#{SIGNATURE_SCHEME}:#{timestamp}:#{payload}")
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
    @delivery.update!(state: :failed, error_message: message)
    record_outcome
  end

  def record_outcome
    @webhook.webhook_delinquency_tracker&.record_delivery(@delivery)
  end
end
