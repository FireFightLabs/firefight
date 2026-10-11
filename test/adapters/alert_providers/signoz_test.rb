require "test_helper"

class AlertProviders::SignozTest < ActiveSupport::TestCase
  setup do
    @source = AlertSource.create!(workspace: workspaces(:slack_workspace_one), name: "SigNoz", provider: AlertSource::PROVIDER_SIGNOZ)
  end

  test "accepts the channel's password, sent as a bearer token with no user name or as Basic auth" do
    basic = "Basic #{Base64.strict_encode64("signoz:#{@source.secret_token}")}"

    assert AlertProviders::Signoz.verify(headers: { "Authorization" => "Bearer #{@source.secret_token}" }, raw_body: "{}", source: @source)
    assert AlertProviders::Signoz.verify(headers: { "Authorization" => basic }, raw_body: "{}", source: @source)
    assert_not AlertProviders::Signoz.verify(headers: { "Authorization" => "Basic #{Base64.strict_encode64('signoz:wrong')}" }, raw_body: "{}", source: @source)
  end

  test "SigNoz's own sample becomes one firing alert, linking to the rule when the label carries it" do
    payload = JSON.parse(file_fixture("alert_providers/signoz.json").read)
    fields = AlertProviders::Signoz.normalize(payload, source: @source).sole[:fields]

    assert_equal "ad592b0afcbe2e79", fields["fingerprint"]
    assert_equal "DiskRunningFull", fields["title"]
    assert_equal "critical", fields["severity_raw"]
    assert_nil fields["url"]

    payload["alerts"].first["labels"]["ruleSource"] = "https://signoz.example.com/alerts/overview?ruleId=7"
    payload["alerts"].first["status"] = "resolved"
    resolved = AlertProviders::Signoz.normalize(payload, source: @source).sole[:fields]
    assert_equal Alert::STATUS_RESOLVED, resolved["status"]
    assert_equal "https://signoz.example.com/alerts/overview?ruleId=7", resolved["url"]
  end
end
