require "test_helper"

class AlertSourcesControllerTest < ActionDispatch::IntegrationTest
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @user = users(:alice)
    sign_in(@user, @workspace)
  end

  test "create generates a source with credentials" do
    post alert_sources_url, params: { alert_source: { name: "Grafana prod" } }

    assert_redirected_to settings_alert_sources_path
    source = @workspace.alert_sources.find_by!(name: "Grafana prod")
    assert source.endpoint_path.present?
    assert source.secret_token.present?
  end

  test "update writes name, enabled, and a validated severity map" do
    source = @workspace.alert_sources.create!(name: "Old", provider: AlertSource::PROVIDER_GENERIC)
    severity = @workspace.incident_severities.active.first

    patch alert_source_url(source), params: {
      alert_source: {
        name: "Renamed",
        enabled: false,
        severity_map: { "Critical" => severity.id, "bogus" => "not-a-severity-id" }
      }
    }

    source.reload
    assert_equal "Renamed", source.name
    assert_not source.enabled
    assert_equal({ "critical" => severity.id }, source.config["severity_map"])
  end

  test "destroy removes the source" do
    source = @workspace.alert_sources.create!(name: "Gone", provider: AlertSource::PROVIDER_GENERIC)

    delete alert_source_url(source)

    assert_nil AlertSource.find_by(id: source.id)
  end

  test "token endpoint returns the secret on demand" do
    source = @workspace.alert_sources.create!(name: "Grafana", provider: AlertSource::PROVIDER_GENERIC)

    post token_alert_source_url(source)

    assert_response :success
    assert_equal source.secret_token, JSON.parse(response.body)["token"]
  end

  test "update persists extraction and dedup config" do
    source = @workspace.alert_sources.create!(name: "Custom", provider: AlertSource::PROVIDER_GENERIC)

    patch alert_source_url(source), params: { alert_source: {
      field_map: { title: "alert.name", bogus: "x" },
      items_path: "alerts",
      fingerprint_fields: [ "service", "" ],
      flap_window_minutes: 999
    } }

    source.reload
    assert_equal({ "title" => "alert.name" }, source.config["field_map"])
    assert_equal "alerts", source.config["items_path"]
    assert_equal [ "service" ], source.fingerprint_fields
    assert_equal AlertSource::FLAP_WINDOW_MINUTES_RANGE.max, source.config["flap_window_minutes"]
  end

  test "sample_payload returns the latest alert's raw payload" do
    source = @workspace.alert_sources.create!(name: "Custom", provider: AlertSource::PROVIDER_GENERIC)
    source.alerts.create!(workspace: @workspace, external_id: "a", fingerprint: "f1",
                          payload: { "old" => true }, fields: {}, received_at: 1.hour.ago, last_seen_at: 1.hour.ago)
    source.alerts.create!(workspace: @workspace, external_id: "b", fingerprint: "f2",
                          payload: { "new" => true }, fields: {}, received_at: Time.current, last_seen_at: Time.current)

    get sample_payload_alert_source_url(source)

    assert_response :success
    assert_equal({ "new" => true }, JSON.parse(response.body)["payload"])
  end

  test "cannot touch another workspace's source" do
    other = workspaces(:slack_workspace_two)
    source = other.alert_sources.create!(name: "Theirs", provider: AlertSource::PROVIDER_GENERIC)

    patch alert_source_url(source), params: { alert_source: { name: "Hijacked" } }

    assert_response :not_found
    assert_equal "Theirs", source.reload.name
  end
end
