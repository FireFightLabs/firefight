require "test_helper"

# A body New Relic's default webhook template renders, as published in a New Relic integration guide, and the same issue
# closed.
class AlertProviders::NewRelicTest < ActiveSupport::TestCase
  setup do
    @source = AlertSource.create!(workspace: workspaces(:slack_workspace_one), name: "New Relic", provider: AlertSource::PROVIDER_NEW_RELIC)
  end

  def fixture(name) = JSON.parse(file_fixture("alert_providers/newrelic_#{name}.json").read)

  test "accepts the destination's bearer token" do
    assert AlertProviders::NewRelic.verify(headers: { "Authorization" => "Bearer #{@source.secret_token}" }, raw_body: "{}", source: @source)
    assert_not AlertProviders::NewRelic.verify(headers: { "Authorization" => "Bearer wrong" }, raw_body: "{}", source: @source)
  end

  test "an activated issue fires and the closed issue resolves it" do
    activated = AlertProviders::NewRelic.normalize(fixture("default"), source: @source).sole[:fields]
    closed = AlertProviders::NewRelic.normalize(fixture("default_closed"), source: @source).sole[:fields]

    assert_equal "issue:00000000-0000-0000-0000-000000000000", activated["fingerprint"]
    assert_equal Alert::STATUS_FIRING, activated["status"]
    assert_equal "newrelicagent query result is > 10.0 for 1 minutes on 'High CPU'", activated["title"]
    assert_equal "CRITICAL", activated["severity_raw"]
    assert_equal "hostname", activated["service"]
    assert_equal "Policy MyPolicy, condition MyAlertCondition", activated["description"]
    assert activated["url"].start_with?("https://")
    assert_equal Alert::STATUS_RESOLVED, closed["status"]
    assert_equal activated["fingerprint"], closed["fingerprint"]
  end
end
