require "test_helper"

class AlertSourcesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @user = users(:alice)
    sign_in(@user, @workspace)
  end

  test "create generates a source with credentials" do
    post alert_sources_url, params: { alert_source: { name: "Grafana prod" } }

    source = @workspace.alert_sources.find_by!(name: "Grafana prod")
    assert_redirected_to settings_alert_sources_path(setup: source.id)
    assert source.endpoint_path.present?
    assert source.secret_token.present?
    assert_equal "Grafana prod was created.", flash[:notice]
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
    assert_equal "Renamed was updated.", flash[:notice]
  end

  test "destroy removes the source" do
    source = @workspace.alert_sources.create!(name: "Gone", provider: AlertSource::PROVIDER_GENERIC)

    delete alert_source_url(source)

    assert_nil AlertSource.find_by(id: source.id)
    assert_equal "Gone was deleted.", flash[:notice]
  end

  test "token endpoint returns the secret on demand" do
    source = @workspace.alert_sources.create!(name: "Grafana", provider: AlertSource::PROVIDER_GENERIC)

    post token_alert_source_url(source)

    assert_response :success
    assert_equal source.secret_token, JSON.parse(response.body)["token"]
  end

  test "a provider that signs with a secret of its own takes the pasted secret, never hands it back, and says it has one" do
    source = @workspace.alert_sources.create!(name: "Sentry", provider: AlertSource::PROVIDER_SENTRY)

    post token_alert_source_url(source)
    assert_response :not_found

    patch alert_source_url(source), params: { alert_source: { secret: "  sentry-client-secret-4f2a  " } }
    source.reload
    assert_equal "sentry-client-secret-4f2a", source.secret_token
    assert_equal "Sentry was updated.", flash[:notice]
    assert_equal "Secret ending in 4f2a. Enter a new one to replace it.", source.secret_summary

    patch alert_source_url(source), params: { alert_source: { name: "Sentry prod", secret: "" } }
    assert_equal "sentry-client-secret-4f2a", source.reload.secret_token
  end

  test "a secret sent for a provider whose token Firefight makes is ignored" do
    source = @workspace.alert_sources.create!(name: "Grafana", provider: AlertSource::PROVIDER_GRAFANA)
    token = source.secret_token

    patch alert_source_url(source), params: { alert_source: { secret: "chosen-by-someone" } }

    assert_equal token, source.reload.secret_token
    assert_nil source.secret_summary
  end

  test "the settings page offers every provider's setup and opens a new source's, never a secret" do
    source = @workspace.alert_sources.create!(name: "Sentry", provider: AlertSource::PROVIDER_SENTRY)
    source.replace_secret("client-secret-value-9z")
    source.save!

    get settings_alert_sources_url(setup: source.id), headers: inertia_headers

    props = response.parsed_body["props"]
    assert_equal source.id, props["setupSourceId"]
    assert_equal AlertSource::PROVIDERS.sort, props["providers"].pluck("provider").sort
    assert_equal "Secret ending in e-9z. Enter a new one to replace it.", props["alertSources"].find { |row| row["id"] == source.id }["secretSummary"]
    assert_not_includes response.body, "client-secret-value-9z"
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

  test "a Logfire source's whole address is fetched on demand, and its token alone is never handed out" do
    source = @workspace.alert_sources.create!(name: "Logfire", provider: AlertSource::PROVIDER_LOGFIRE)

    post address_alert_source_url(source)
    assert_response :success
    assert_equal "#{api_v1_alert_ingest_path(endpoint_path: source.endpoint_path)}/#{source.secret_token}", response.parsed_body["path"]

    post token_alert_source_url(source)
    assert_response :not_found
  end

  test "a source whose token travels in a header has no address to fetch or regenerate" do
    source = @workspace.alert_sources.create!(name: "Webhook", provider: AlertSource::PROVIDER_GENERIC)
    token = source.secret_token

    post address_alert_source_url(source)
    assert_response :not_found
    post regenerate_address_alert_source_url(source)
    assert_response :not_found
    assert_equal token, source.reload.secret_token
  end

  test "regenerating a Logfire source's address replaces its secret and says so" do
    source = @workspace.alert_sources.create!(name: "Logfire", provider: AlertSource::PROVIDER_LOGFIRE)
    old_secret = source.secret_token

    post regenerate_address_alert_source_url(source)

    assert_redirected_to settings_alert_sources_path
    assert_equal "Logfire has a new address.", flash[:notice]
    assert_not_equal old_secret, source.reload.secret_token
    assert_equal 48, source.secret_token.length
  end

  test "the settings page shows a Logfire source's address masked, never its secret" do
    source = @workspace.alert_sources.create!(name: "Logfire", provider: AlertSource::PROVIDER_LOGFIRE)

    get settings_alert_sources_url, headers: inertia_headers

    row = response.parsed_body["props"]["alertSources"].find { |entry| entry["id"] == source.id }
    assert_equal "#{api_v1_alert_ingest_path(endpoint_path: source.endpoint_path)}/#{AlertSourceSettingsSerializer::SECRET_MASK}", row["ingestPath"]
    assert response.parsed_body["props"]["providers"].find { |entry| entry["provider"] == AlertSource::PROVIDER_LOGFIRE }["secretInAddress"]
    assert_not_includes response.body, source.secret_token
  end
end
