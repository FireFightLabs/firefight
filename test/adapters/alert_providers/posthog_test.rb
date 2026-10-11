require "test_helper"

# The insight and logs alert bodies are rendered from the templates in PostHog's own source, since PostHog's docs
# publish none.
class AlertProviders::PosthogTest < ActiveSupport::TestCase
  setup do
    @source = AlertSource.create!(workspace: workspaces(:slack_workspace_one), name: "PostHog", provider: AlertSource::PROVIDER_POSTHOG)
  end

  def fixture(name) = file_fixture("alert_providers/posthog_#{name}.json").read

  # Signed the way Standard Webhooks' reference library does, with the token as the base64 secret.
  def signed_headers(body, id: "4b1e1c56-1f0a-4b8e-9a4e-6f0c2d7b8a91", timestamp: Time.current.to_i, secret: @source.secret_token)
    key = Base64.decode64(secret)
    signature = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", key, "#{id}.#{timestamp}.#{body}"))
    { "webhook-id" => id, "webhook-timestamp" => timestamp.to_s, "webhook-signature" => "v1,#{signature}" }
  end

  test "accepts a Standard Webhooks signature made with the token, among several" do
    body = fixture("insight_alert")
    headers = signed_headers(body)
    headers["webhook-signature"] = "v1,bm90IGl0 #{headers['webhook-signature']}"

    assert AlertProviders::Posthog.verify(headers: headers, raw_body: body, source: @source)
  end

  test "refuses a wrong secret, a changed body, a stale timestamp and a missing id" do
    body = fixture("insight_alert")

    assert_not AlertProviders::Posthog.verify(headers: signed_headers(body, secret: Base64.strict_encode64("x" * 32)), raw_body: body, source: @source)
    assert_not AlertProviders::Posthog.verify(headers: signed_headers(body), raw_body: "#{body} ", source: @source)
    assert_not AlertProviders::Posthog.verify(headers: signed_headers(body, timestamp: 10.minutes.ago.to_i), raw_body: body, source: @source)
    assert_not AlertProviders::Posthog.verify(headers: signed_headers(body).except("webhook-id"), raw_body: body, source: @source)
  end

  test "each insight alert delivery is its own firing alert, linking to the alert" do
    payload = JSON.parse(fixture("insight_alert"))
    fields = AlertProviders::Posthog.normalize(payload, source: @source, headers: { "webhook-id" => "delivery-1" }).sole[:fields]
    later = AlertProviders::Posthog.normalize(payload, source: @source, headers: { "webhook-id" => "delivery-2" }).sole[:fields]

    assert_equal({ "external_id" => "delivery-1", "fingerprint" => "insight_alert:01936c4e-8f2a-7b3c-9d1e-2f4a6b8c0d1e:delivery-1",
                   "status" => Alert::STATUS_FIRING, "title" => "Signups dropped", "service" => "Daily signups",
                   "description" => "The insight value for Signups (0) is less than lower threshold (100)",
                   "url" => payload["alert_url"] }, fields)
    assert_not_equal fields["fingerprint"], later["fingerprint"]
  end

  test "a logs alert fires and its resolve reaches the same alert" do
    firing = AlertProviders::Posthog.normalize(JSON.parse(fixture("logs_alert_firing")), source: @source).sole[:fields]
    resolved = AlertProviders::Posthog.normalize(JSON.parse(fixture("logs_alert_resolved")), source: @source).sole[:fields]

    assert_equal "logs_alert:01936c50-aaaa-7bbb-8ccc-dddddddddddd", firing["fingerprint"]
    assert_equal "42 matching logs, alerting above 10 in 5 minutes.", firing["description"]
    assert_equal "checkout", firing["service"]
    assert_equal Alert::STATUS_RESOLVED, resolved["status"]
    assert_equal firing["fingerprint"], resolved["fingerprint"]
  end
end
