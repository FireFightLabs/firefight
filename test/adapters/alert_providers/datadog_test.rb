require "test_helper"

# Bodies rendered from AlertProviders::Datadog::TEMPLATE with the variable values Datadog's Webhooks docs give.
class AlertProviders::DatadogTest < ActiveSupport::TestCase
  setup do
    @source = AlertSource.create!(workspace: workspaces(:slack_workspace_one), name: "Datadog", provider: AlertSource::PROVIDER_DATADOG)
  end

  def fixture(name) = JSON.parse(file_fixture("alert_providers/datadog_#{name}.json").read)

  test "accepts the token in the webhook's custom header" do
    assert AlertProviders::Datadog.verify(headers: { "X-Firefight-Token" => @source.secret_token }, raw_body: "{}", source: @source)
    assert_not AlertProviders::Datadog.verify(headers: { "X-Firefight-Token" => "wrong" }, raw_body: "{}", source: @source)
  end

  test "the template names every field the adapter reads" do
    template = JSON.parse(AlertProviders::Datadog::TEMPLATE)

    assert_equal fixture("triggered").keys.sort, template.keys.sort
  end

  test "a trigger fires on the alert cycle, and the recovery resolves the same alert under the same title" do
    triggered = AlertProviders::Datadog.normalize(fixture("triggered"), source: @source).sole[:fields]
    recovered = AlertProviders::Datadog.normalize(fixture("recovered"), source: @source).sole[:fields]

    assert_equal({ "external_id" => "7812345678901234567", "fingerprint" => "cycle:7812345678901230000", "status" => Alert::STATUS_FIRING,
                   "title" => "High CPU on checkout-api", "description" => "CPU usage is above 90% on checkout-api.\n@webhook-firefight",
                   "service" => "checkout-api", "severity_raw" => "P2", "team" => "payments", "environment" => "prod",
                   "url" => "https://app.datadoghq.com/event/jump_to?event_id=7812345678901234567" }, triggered)
    assert_equal Alert::STATUS_RESOLVED, recovered["status"]
    assert_equal triggered.values_at("fingerprint", "title"), recovered.values_at("fingerprint", "title")
  end

  test "Datadog's default body, which says nothing of the transition, is unrecognized" do
    default = { "body" => "%%%\nCPU high\n%%%", "event_type" => "query_alert_monitor", "title" => "[Triggered] CPU", "id" => "1" }

    assert_empty AlertProviders::Datadog.normalize(default, source: @source)
  end
end
