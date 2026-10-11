require "test_helper"

class AlertProviders::HoneycombTest < ActiveSupport::TestCase
  setup do
    @source = AlertSource.create!(workspace: workspaces(:slack_workspace_one), name: "Honeycomb", provider: AlertSource::PROVIDER_HONEYCOMB)
  end

  def fixture(name) = JSON.parse(file_fixture("alert_providers/honeycomb_#{name}.json").read)

  test "accepts the token Honeycomb sends as the recipient's shared secret" do
    assert AlertProviders::Honeycomb.verify(headers: { "X-Honeycomb-Webhook-Token" => @source.secret_token }, raw_body: "{}", source: @source)
    assert_not AlertProviders::Honeycomb.verify(headers: { "X-Honeycomb-Webhook-Token" => "wrong" }, raw_body: "{}", source: @source)
  end

  test "a trigger fires keyed on the trigger and named by the delivery, OK resolves it, and the secret is never kept" do
    payload = fixture("trigger").merge("shared_secret" => @source.secret_token)
    triggered = AlertProviders::Honeycomb.normalize(payload, source: @source, headers: { "X-Honeycomb-Webhook-Delivery-ID" => "d-1" }).sole
    resolved = AlertProviders::Honeycomb.normalize(fixture("trigger_resolved"), source: @source).sole[:fields]

    assert_equal "d-1", triggered[:fields]["external_id"]
    assert_equal "trigger:abdcefg", triggered[:fields]["fingerprint"]
    assert_equal "trig on ttt", triggered[:fields]["title"]
    assert triggered[:fields]["url"].start_with?("https://ui.honeycomb.io/")
    assert_not triggered[:payload].key?("shared_secret")
    assert_equal Alert::STATUS_RESOLVED, resolved["status"]
    assert_equal triggered[:fields]["fingerprint"], resolved["fingerprint"]
  end
end
