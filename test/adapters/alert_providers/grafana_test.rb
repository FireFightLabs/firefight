require "test_helper"

class AlertProviders::GrafanaTest < ActiveSupport::TestCase
  setup do
    @source = AlertSource.create!(workspace: workspaces(:slack_workspace_one), name: "Grafana", provider: AlertSource::PROVIDER_GRAFANA)
  end

  def fixture(name) = file_fixture("alert_providers/#{name}.json").read

  test "accepts the contact point's bearer credentials" do
    assert AlertProviders::Grafana.verify(headers: { "Authorization" => "Bearer #{@source.secret_token}" }, raw_body: "{}", source: @source)
    assert_not AlertProviders::Grafana.verify(headers: { "Authorization" => "Bearer nope" }, raw_body: "{}", source: @source)
  end

  test "accepts an HMAC signature of the body, and of the timestamp and body when a timestamp header is sent" do
    body = fixture("grafana_firing")
    timestamp = Time.current.to_i.to_s
    signed = OpenSSL::HMAC.hexdigest("SHA256", @source.secret_token, body)
    signed_with_time = OpenSSL::HMAC.hexdigest("SHA256", @source.secret_token, "#{timestamp}:#{body}")

    assert AlertProviders::Grafana.verify(headers: { "X-Grafana-Alerting-Signature" => signed }, raw_body: body, source: @source)
    assert AlertProviders::Grafana.verify(headers: { "X-Grafana-Alerting-Signature" => signed_with_time, "X-Grafana-Alerting-Timestamp" => timestamp },
                                          raw_body: body, source: @source)
    assert_not AlertProviders::Grafana.verify(headers: { "X-Grafana-Alerting-Signature" => signed }, raw_body: "#{body} ", source: @source)
  end

  test "a signature with a stale timestamp is refused" do
    body = fixture("grafana_firing")
    stale = 10.minutes.ago.to_i.to_s
    signature = OpenSSL::HMAC.hexdigest("SHA256", @source.secret_token, "#{stale}:#{body}")

    assert_not AlertProviders::Grafana.verify(headers: { "X-Grafana-Alerting-Signature" => signature, "X-Grafana-Alerting-Timestamp" => stale },
                                              raw_body: body, source: @source)
  end

  test "a firing group is one alert per entry, and the resolve reaches the same fingerprint" do
    firing = AlertProviders::Grafana.normalize(JSON.parse(fixture("grafana_firing")), source: @source)
    resolved = AlertProviders::Grafana.normalize(JSON.parse(fixture("grafana_resolved")), source: @source)

    assert_equal 2, firing.size
    first = firing.first[:fields]
    assert_equal "High memory usage", first["title"]
    assert_equal "blue", first["team"]
    assert_equal "https://play.grafana.org/alerting/1afz29v7z/edit", first["url"]
    assert_includes first["description"], "high memory usage"
    assert_equal Alert::STATUS_RESOLVED, resolved.first[:fields]["status"]
    assert_equal first["fingerprint"], resolved.first[:fields]["fingerprint"]
  end
end
