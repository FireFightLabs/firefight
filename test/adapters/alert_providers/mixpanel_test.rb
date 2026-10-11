require "test_helper"

class AlertProviders::MixpanelTest < ActiveSupport::TestCase
  setup do
    @source = AlertSource.create!(workspace: workspaces(:slack_workspace_one), name: "Mixpanel", provider: AlertSource::PROVIDER_MIXPANEL)
    @payload = JSON.parse(file_fixture("alert_providers/mixpanel_alert.json").read)
  end

  test "accepts the token as the webhook's Basic auth password, whatever the user name" do
    basic = ->(password) { { "Authorization" => "Basic #{Base64.strict_encode64("anyone:#{password}")}" } }

    assert AlertProviders::Mixpanel.verify(headers: basic.call(@source.secret_token), raw_body: "{}", source: @source)
    assert_not AlertProviders::Mixpanel.verify(headers: basic.call("wrong"), raw_body: "{}", source: @source)
    assert_not AlertProviders::Mixpanel.verify(headers: { "Authorization" => "Basic not-base64!" }, raw_body: "{}", source: @source)
    assert_not AlertProviders::Mixpanel.verify(headers: { "Authorization" => "Bearer #{@source.secret_token}" }, raw_body: "{}", source: @source)
  end

  test "a triggered alert fires, linking to the report, and each trigger is its own alert" do
    fields = AlertProviders::Mixpanel.normalize(@payload, source: @source).sole[:fields]
    @payload["alert"]["fired_at"] = "2026-02-07T10:53:30Z"
    later = AlertProviders::Mixpanel.normalize(@payload, source: @source).sole[:fields]

    assert_equal "Webhook Test", fields["title"]
    assert_equal Alert::STATUS_FIRING, fields["status"]
    assert_equal "My Prod project", fields["service"]
    assert_equal "Custom Alert Insights Report is above 0. Current value 20,000", fields["description"]
    assert fields["url"].start_with?("https://mixpanel.com/project/9876543/")
    assert_not_equal fields["fingerprint"], later["fingerprint"]
  end
end
