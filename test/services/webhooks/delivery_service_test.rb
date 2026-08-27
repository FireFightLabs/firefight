require "test_helper"

class Webhooks::DeliveryServiceTest < ActiveSupport::TestCase
  setup do
    @webhook = webhooks(:active_webhook)
    @event = incident_events(:inc1_created)
    @delivery = WebhookDelivery.new(
      webhook: @webhook,
      incident_event: @event,
      event_type: @event.event_type
    )
    @delivery.save!(validate: true)
    # Reset state since after_create_commit enqueues delivery job
    @delivery.update_columns(state: "pending")
  end

  test "delivers successfully to a 200 endpoint" do
    stub_ssrf_resolution("93.184.216.34")
    stub_http_response(200)

    Webhooks::DeliveryService.deliver(@delivery)

    @delivery.reload
    assert_equal "succeeded", @delivery.state
    assert_equal 200, @delivery.response_code
    assert_not_nil @delivery.delivered_at
    assert_not_nil @delivery.request_headers
    assert_not_nil @delivery.request_body
  end

  test "records HMAC signature, version, timestamp, and attempt headers" do
    stub_ssrf_resolution("93.184.216.34")
    stub_http_response(200)

    Webhooks::DeliveryService.deliver(@delivery)

    @delivery.reload
    headers = @delivery.request_headers
    assert headers.key?("X-Webhook-Signature")
    assert_match(/\Av1=[a-f0-9]{64}\z/, headers["X-Webhook-Signature"])
    assert_equal @event.event_type, headers["X-Webhook-Event"]
    assert_equal Webhooks::DeliveryService::PAYLOAD_VERSION, headers["X-Webhook-Version"]
    assert_equal "1", headers["X-Webhook-Attempt"]
    assert_not_nil headers["X-Webhook-Timestamp"]
    assert_nothing_raised { Time.iso8601(headers["X-Webhook-Timestamp"]) }
  end

  test "increments attempts counter on each deliver" do
    stub_ssrf_resolution("93.184.216.34")
    stub_http_response(200)

    Webhooks::DeliveryService.deliver(@delivery)
    assert_equal 1, @delivery.reload.attempts

    @delivery.update_columns(state: "pending")
    Webhooks::DeliveryService.deliver(@delivery)
    assert_equal 2, @delivery.reload.attempts
  end

  test "reuses signed_payload bytes on retry so consumers see immutable body" do
    stub_ssrf_resolution("93.184.216.34")
    stub_http_response(200)

    Webhooks::DeliveryService.deliver(@delivery)
    first_payload = @delivery.reload.signed_payload
    assert_not_nil first_payload

    @event.incident.update_columns(name: "Drifted name")
    @delivery.update_columns(state: "pending")

    Webhooks::DeliveryService.deliver(@delivery)
    assert_equal first_payload, @delivery.reload.signed_payload
  end

  test "a non-2xx response is a failed delivery with the code, never a delivered one" do
    stub_ssrf_resolution("93.184.216.34")
    stub_http_response(503)

    Webhooks::DeliveryService.deliver(@delivery)

    @delivery.reload
    assert_equal "failed", @delivery.state
    assert_equal 503, @delivery.response_code
    assert_equal "http_503", @delivery.error_message
    assert_nil @delivery.delivered_at
  end

  test "marks delivery failed for private IP" do
    Webhooks::SsrfProtector.stubs(:resolve_public_ip).returns(nil)

    Webhooks::DeliveryService.deliver(@delivery)

    @delivery.reload
    assert_equal "failed", @delivery.state
    assert_equal "private_uri", @delivery.error_message
  end

  test "marks delivery failed on connection timeout" do
    stub_ssrf_resolution("93.184.216.34")
    Net::HTTP.any_instance.stubs(:request).raises(Net::OpenTimeout)

    Webhooks::DeliveryService.deliver(@delivery)

    @delivery.reload
    assert_equal "failed", @delivery.state
    assert_equal "connection_timeout", @delivery.error_message
  end

  test "marks delivery failed on connection refused" do
    stub_ssrf_resolution("93.184.216.34")
    Net::HTTP.any_instance.stubs(:request).raises(Errno::ECONNREFUSED)

    Webhooks::DeliveryService.deliver(@delivery)

    @delivery.reload
    assert_equal "failed", @delivery.state
    assert_equal "destination_unreachable", @delivery.error_message
  end

  test "marks delivery failed on TLS failure" do
    stub_ssrf_resolution("93.184.216.34")
    Net::HTTP.any_instance.stubs(:request).raises(OpenSSL::SSL::SSLError)

    Webhooks::DeliveryService.deliver(@delivery)

    @delivery.reload
    assert_equal "failed", @delivery.state
    assert_equal "failed_tls", @delivery.error_message
  end

  test "records delinquency on failure" do
    stub_ssrf_resolution("93.184.216.34")
    Net::HTTP.any_instance.stubs(:request).raises(Net::OpenTimeout)

    tracker = @webhook.webhook_delinquency_tracker
    assert_equal 0, tracker.consecutive_failures_count

    Webhooks::DeliveryService.deliver(@delivery)

    assert_equal 1, tracker.reload.consecutive_failures_count
  end

  test "tells the workspace when a failure deactivates the webhook" do
    stub_ssrf_resolution("93.184.216.34")
    Net::HTTP.any_instance.stubs(:request).raises(Net::OpenTimeout)
    @webhook.webhook_delinquency_tracker.update_columns(
      consecutive_failures_count: WebhookDelinquencyTracker::DELINQUENCY_THRESHOLD - 1,
      first_failure_at: 2.hours.ago
    )
    Webhooks::DeactivationNotifier.expects(:notify).with(@webhook, reason: WebhookDelinquencyTracker::DEACTIVATION_REASON).once

    Webhooks::DeliveryService.deliver(@delivery)

    assert_not @webhook.reload.active?
  end

  test "signature is HMAC-SHA256 over scheme:timestamp:body" do
    stub_ssrf_resolution("93.184.216.34")

    captured = {}
    Net::HTTP.any_instance.stubs(:request).with do |request|
      captured[:signature] = request["X-Webhook-Signature"]
      captured[:timestamp] = request["X-Webhook-Timestamp"]
      captured[:body] = request.body
      true
    end.returns(stub(code: "200", read_body: nil))

    Webhooks::DeliveryService.deliver(@delivery)

    signing_input = "v1:#{captured[:timestamp]}:#{captured[:body]}"
    expected = "v1=" + OpenSSL::HMAC.hexdigest("SHA256", @webhook.signing_secret, signing_input)
    assert_equal expected, captured[:signature]
  end

  private

  def stub_ssrf_resolution(ip)
    Webhooks::SsrfProtector.stubs(:resolve_public_ip).returns(ip)
  end

  def stub_http_response(code)
    response = stub(code: code.to_s, read_body: nil)
    Net::HTTP.any_instance.stubs(:request).returns(response)
  end
end
