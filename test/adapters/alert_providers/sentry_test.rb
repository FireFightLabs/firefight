require "test_helper"

# Sentry's documented samples. The critical metric alert is the documented resolved one with the action and status
# Sentry's source sets for critical, and the resolved issue is the documented issue webhook for the alerted issue.
class AlertProviders::SentryTest < ActiveSupport::TestCase
  CLIENT_SECRET = "7e8b5f5c1c2a4d8f9b0e6a3d2c1f0e9d8c7b6a5f4e3d2c1b0a9f8e7d6c5b4a39".freeze

  setup do
    @source = AlertSource.create!(workspace: workspaces(:slack_workspace_one), name: "Sentry", provider: AlertSource::PROVIDER_SENTRY)
    @source.replace_secret(CLIENT_SECRET)
    @source.save!
  end

  def raw(name) = file_fixture("alert_providers/sentry_#{name}.json").read
  def fields_for(name) = AlertProviders::Sentry.normalize(JSON.parse(raw(name)), source: @source).sole[:fields]

  test "accepts a body signed with the client secret, as Sentry signs it, and nothing else" do
    body = raw("event_alert")
    signature = OpenSSL::HMAC.hexdigest("SHA256", CLIENT_SECRET, body)

    assert AlertProviders::Sentry.verify(headers: { "Sentry-Hook-Signature" => signature }, raw_body: body, source: @source)
    assert_not AlertProviders::Sentry.verify(headers: { "Sentry-Hook-Signature" => signature }, raw_body: body.sub("heck", "oops"), source: @source)
    assert_not AlertProviders::Sentry.verify(headers: { "Sentry-Hook-Signature" => OpenSSL::HMAC.hexdigest("SHA256", "other", body) },
                                             raw_body: body, source: @source)
    assert_not AlertProviders::Sentry.verify(headers: { "X-Firefight-Token" => CLIENT_SECRET }, raw_body: body, source: @source)
  end

  test "an issue alert fires on its issue, and the issue resolving in Sentry resolves it" do
    fired = fields_for("event_alert")
    resolved = fields_for("issue_resolved")

    assert_equal({ "external_id" => "event:e4874d664c3540c1a32eab185f12c5ab:Very Important Alert!", "fingerprint" => "issue:1117540176",
                   "status" => Alert::STATUS_FIRING, "title" => "ReferenceError: heck is not defined",
                   "description" => "heck is not defined\n?(<anonymous>)", "service" => "front-end", "severity_raw" => "error",
                   "url" => "https://sentry.io/organizations/test-org/issues/1117540176/events/e4874d664c3540c1a32eab185f12c5ab/" },
                 fired.except("environment"))
    assert_equal Alert::STATUS_RESOLVED, resolved["status"]
    assert_equal fired["fingerprint"], resolved["fingerprint"]
  end

  test "a critical metric alert fires under its rule's name and the resolve reaches it" do
    critical = fields_for("metric_alert_critical")
    resolved = fields_for("metric_alert_resolved")

    assert_equal "metric:4", critical["fingerprint"]
    assert_equal "Too many errors", critical["title"]
    assert_equal "critical", critical["severity_raw"]
    assert_equal "bar", critical["service"]
    assert_equal "https://sentry.io/organizations/baz/alerts/1/", critical["url"]
    assert_equal Alert::STATUS_RESOLVED, resolved["status"]
    assert_equal critical["fingerprint"], resolved["fingerprint"]
  end

  test "an issue being created is accepted and ignored" do
    created = JSON.parse(raw("issue_created"))

    assert_empty AlertProviders::Sentry.normalize(created, source: @source)
    assert AlertProviders::Sentry.ignored?(created)
    assert_not AlertProviders::Sentry.ignored?(JSON.parse(raw("event_alert")))
  end
end
