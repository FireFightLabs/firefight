require "test_helper"

class AlertProviders::AlertmanagerTest < ActiveSupport::TestCase
  setup do
    @source = AlertSource.create!(workspace: workspaces(:slack_workspace_one), name: "Prometheus", provider: AlertSource::PROVIDER_ALERTMANAGER)
  end

  def payload = JSON.parse(file_fixture("alert_providers/alertmanager.json").read)

  test "accepts the token as a bearer credential, a custom header or a Basic auth password" do
    basic = "Basic #{Base64.strict_encode64("alertmanager:#{@source.secret_token}")}"

    assert AlertProviders::Alertmanager.verify(headers: { "Authorization" => "Bearer #{@source.secret_token}" }, raw_body: "{}", source: @source)
    assert AlertProviders::Alertmanager.verify(headers: { "X-Firefight-Token" => @source.secret_token }, raw_body: "{}", source: @source)
    assert AlertProviders::Alertmanager.verify(headers: { "Authorization" => basic }, raw_body: "{}", source: @source)
    assert_not AlertProviders::Alertmanager.verify(headers: { "Authorization" => "Bearer wrong" }, raw_body: "{}", source: @source)
    assert_not AlertProviders::Alertmanager.verify(headers: {}, raw_body: "{}", source: @source)
  end

  test "each alert in a group is its own alert, firing or resolved, keyed on its fingerprint" do
    firing, resolved = AlertProviders::Alertmanager.normalize(payload, source: @source)

    assert_equal "6f2c1a9e0d3b4c57", firing[:fields]["fingerprint"]
    assert_equal Alert::STATUS_FIRING, firing[:fields]["status"]
    assert_equal "HighErrorRate", firing[:fields]["title"]
    assert_equal "checkout", firing[:fields]["service"]
    assert_equal "critical", firing[:fields]["severity_raw"]
    assert firing[:fields]["url"].start_with?("http")
    assert_equal payload["alerts"].first, firing[:payload]
    assert_equal Alert::STATUS_RESOLVED, resolved[:fields]["status"]
  end

  test "a body without alerts is unrecognized" do
    assert_empty AlertProviders::Alertmanager.normalize({ "status" => "firing" }, source: @source)
  end
end
