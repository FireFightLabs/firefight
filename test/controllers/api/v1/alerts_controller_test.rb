require "test_helper"

class Api::V1::AlertsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @source = AlertSource.create!(workspace: @workspace, name: "Grafana prod", provider: AlertSource::PROVIDER_GENERIC)
  end

  def post_alert(payload, token: @source.secret_token, path: @source.endpoint_path)
    post api_v1_alert_ingest_path(endpoint_path: path),
         params: payload.to_json,
         headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{token}" }
  end

  test "a payload its provider sends on purpose and turns into no alert is accepted with nothing stored, and anything else is refused" do
    AlertProviders::Generic.stubs(:normalize).returns([])
    AlertProviders::Generic.stubs(:ignored?).returns(true)
    post_alert({ "event" => "ping" })

    assert_response :success
    assert_equal({ "ok" => true, "received" => 0, "failed" => 0 }, response.parsed_body)
    assert_equal 0, @source.alerts.count
    assert @source.reload.last_received_at.present?

    AlertProviders::Generic.unstub(:ignored?)
    post_alert({ "event" => "ping" })
    assert_response :unprocessable_entity
  end

  test "unknown endpoint path returns 404" do
    post_alert({ "title" => "x" }, path: "nope")
    assert_response :not_found
  end

  test "disabled source returns 404" do
    @source.update!(enabled: false)
    post_alert({ "title" => "x" })
    assert_response :not_found
  end

  test "wrong token returns 401 and stores nothing" do
    post_alert({ "title" => "x" }, token: "wrong")

    assert_response :unauthorized
    assert_equal 0, @source.alerts.count
  end

  test "valid alert is normalized and persisted" do
    post_alert({ "id" => "evt-1", "title" => "DB down", "severity" => "critical", "service" => "api", "status" => "firing" })

    assert_response :success
    alert = @source.alerts.find_by!(external_id: "evt-1")
    assert_equal "DB down", alert.fields["title"]
    assert_equal "critical", alert.fields["severity_raw"]
    assert_equal "api", alert.fields["service"]
    assert_equal Alert::STATUS_FIRING, alert.status
  end

  test "oversized payload is rejected with 413 and recorded on the source" do
    post api_v1_alert_ingest_path(endpoint_path: @source.endpoint_path),
         params: { "title" => "x" * (AlertSource::StormControl::MAX_PAYLOAD_BYTES + 1) }.to_json,
         headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{@source.secret_token}" }

    assert_response :content_too_large
    assert_equal "payload too large", @source.reload.last_rejection_reason
    assert_equal 0, @source.alerts.count
  end

  test "oversized batches are rejected" do
    items = Array.new(AlertSource::StormControl::MAX_BATCH_ITEMS + 1) { |i| AlertProviders::Base.item({ "title" => "a#{i}" }, {}) }
    AlertProviders::Generic.stubs(:normalize).returns(items)

    post_alert({ "whatever" => true })

    assert_response :unprocessable_entity
    assert_equal "batch too large", @source.reload.last_rejection_reason
  end

  test "rate limit counts items, not requests" do
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    @source.update!(config: { "rate_limit_per_minute" => 3 })
    items = Array.new(4) { |i| AlertProviders::Base.item({ "title" => "a#{i}", "external_id" => "e#{i}" }, {}) }
    AlertProviders::Generic.stubs(:normalize).returns(items)

    post_alert({ "whatever" => true })

    assert_response :too_many_requests
    assert_equal "rate limited", @source.reload.last_rejection_reason
    assert_equal 0, @source.alerts.count
  end

  test "one bad item does not fail the batch" do
    items = [
      AlertProviders::Base.item({ "title" => "good", "external_id" => "g1" }, {}),
      AlertProviders::Base.item({ "title" => "bad", "external_id" => "b1" }, {})
    ]
    AlertProviders::Generic.stubs(:normalize).returns(items)
    AlertIngestService.any_instance.stubs(:ingest).with { |fields, _| fields["title"] == "good" }.returns(nil)
    AlertIngestService.any_instance.stubs(:ingest).with { |fields, _| fields["title"] == "bad" }.raises(StandardError.new("boom"))

    post_alert({ "whatever" => true })

    assert_response :success
    body = JSON.parse(response.body)
    assert_not body["ok"]
    assert_equal 1, body["failed"]
  end

  test "successful ingest stamps last_received_at" do
    post_alert({ "id" => "evt-9", "title" => "x" })

    assert_response :success
    assert @source.reload.last_received_at.present?
  end

  test "token in X-Firefight-Token header also authenticates" do
    post api_v1_alert_ingest_path(endpoint_path: @source.endpoint_path),
         params: { "title" => "x" }.to_json,
         headers: { "Content-Type" => "application/json", "X-Firefight-Token" => @source.secret_token }

    assert_response :success
  end

  test "repeat delivery dedups to one row" do
    2.times { post_alert({ "title" => "DB down", "service" => "api" }) }

    assert_response :success
    assert_equal 1, @source.alerts.count
    assert_equal 2, @source.alerts.first.event_count
  end

  # With a JSON content type Rails rejects malformed bodies before the controller runs.
  # This covers the non-JSON path where the controller parses raw_post itself.
  test "invalid JSON body returns 400" do
    post api_v1_alert_ingest_path(endpoint_path: @source.endpoint_path),
         params: "not-json{",
         headers: { "Content-Type" => "text/plain", "Authorization" => "Bearer #{@source.secret_token}" }

    assert_response :bad_request
  end

  test "unrecognizable payload returns 422" do
    post api_v1_alert_ingest_path(endpoint_path: @source.endpoint_path),
         params: [ 1, 2 ].to_json,
         headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{@source.secret_token}" }

    assert_response :unprocessable_entity
    assert_equal 0, @source.alerts.count
  end

  test "northflank source authenticates via its token header and normalizes the event" do
    source = AlertSource.create!(workspace: @workspace, name: "Northflank", provider: AlertSource::PROVIDER_NORTHFLANK)
    payload = {
      "event" => "container:crash",
      "data" => {
        "service" => { "id" => "website", "name" => "Website" },
        "project" => { "id" => "blog", "name" => "Blog" }
      }
    }

    post "/api/v1/alerts/#{source.endpoint_path}",
         params: payload.to_json,
         headers: {
           "Content-Type" => "application/json",
           AlertProviders::Northflank::TOKEN_HEADER => source.secret_token
         }

    assert_response :success
    alert = source.alerts.sole
    assert_equal "container:crash", alert.fields["event"]
    assert_equal "website", alert.fields["service"]
    assert_equal "Container crash: Website (Blog)", alert.title
  end

  test "pagerduty's ping is accepted with nothing stored, and a triggered incident becomes an alert" do
    source = AlertSource.create!(workspace: @workspace, name: "PagerDuty", provider: AlertSource::PROVIDER_PAGERDUTY)
    headers = { "Content-Type" => "application/json", AlertProviders::Pagerduty::TOKEN_HEADER => source.secret_token }
    ping = { "event" => { "id" => "p1", "event_type" => "pagey.ping", "data" => { "type" => "ping" } } }

    post "/api/v1/alerts/#{source.endpoint_path}", params: ping.to_json, headers: headers

    assert_response :success
    assert_equal 0, source.alerts.count

    triggered = { "event" => { "id" => "e1", "event_type" => "incident.triggered",
                               "data" => { "id" => "PGR0VU2", "type" => "incident", "title" => "A little bump in the road", "number" => 2 } } }
    post "/api/v1/alerts/#{source.endpoint_path}", params: triggered.to_json, headers: headers

    assert_response :success
    assert_equal "A little bump in the road", source.alerts.sole.title
  end

  test "rate limit returns 429 before verification work" do
    Rails.cache.stubs(:increment).returns(AlertSource::DEFAULT_RATE_LIMIT_PER_MINUTE + 1)

    post_alert({ "title" => "x" })

    assert_response :too_many_requests
    assert_equal 0, @source.alerts.count
  end

  def post_raw(source, body, headers)
    post api_v1_alert_ingest_path(endpoint_path: source.endpoint_path), params: body, headers: { "Content-Type" => "application/json" }.merge(headers)
  end

  def fixture_body(name) = file_fixture("alert_providers/#{name}.json").read

  test "the generic webhook takes the token as a Basic auth password" do
    post api_v1_alert_ingest_path(endpoint_path: @source.endpoint_path),
         params: { "title" => "Disk full" }.to_json,
         headers: { "Content-Type" => "application/json", "Authorization" => "Basic #{Base64.strict_encode64("any:#{@source.secret_token}")}" }

    assert_response :success
    assert_equal "Disk full", @source.alerts.sole.title
  end

  test "a Sentry issue alert signed with the pasted client secret fires, and the issue resolving resolves it" do
    source = AlertSource.create!(workspace: @workspace, name: "Sentry", provider: AlertSource::PROVIDER_SENTRY)
    secret = SecureRandom.hex(32)
    fired = fixture_body("sentry_event_alert")

    post_raw(source, fired, "Sentry-Hook-Signature" => OpenSSL::HMAC.hexdigest("SHA256", secret, fired))
    assert_response :unauthorized
    assert_equal "invalid token", source.reload.last_rejection_reason

    source.replace_secret(secret)
    source.save!
    post_raw(source, fired, "Sentry-Hook-Signature" => OpenSSL::HMAC.hexdigest("SHA256", secret, fired))
    assert_response :success
    alert = source.alerts.sole
    assert_predicate alert, :firing?
    assert_equal alert.fields["url"], alert.source_url

    resolved = fixture_body("sentry_issue_resolved")
    post_raw(source, resolved, "Sentry-Hook-Signature" => OpenSSL::HMAC.hexdigest("SHA256", secret, resolved))
    assert_response :success
    assert_equal Alert::STATUS_RESOLVED, alert.reload.status

    created = fixture_body("sentry_issue_created")
    post_raw(source, created, "Sentry-Hook-Signature" => OpenSSL::HMAC.hexdigest("SHA256", secret, created))
    assert_response :success
    assert_equal 1, source.alerts.count
  end

  test "a Grafana group becomes one alert per entry, and a redelivery adds none" do
    source = AlertSource.create!(workspace: @workspace, name: "Grafana", provider: AlertSource::PROVIDER_GRAFANA)
    body = fixture_body("grafana_firing")
    headers = { "Authorization" => "Bearer #{source.secret_token}" }

    post_raw(source, body, headers)
    post_raw(source, body, headers)

    assert_response :success
    assert_equal 2, source.alerts.count
    assert_equal [ 2, 2 ], source.alerts.order(:created_at).pluck(:event_count)
    post_raw(source, fixture_body("grafana_resolved"), headers)
    assert_equal [ Alert::STATUS_FIRING, Alert::STATUS_RESOLVED ].sort, source.alerts.pluck(:status).sort
  end

  test "a Mixpanel alert authenticates with the token as its Basic auth password" do
    source = AlertSource.create!(workspace: @workspace, name: "Mixpanel", provider: AlertSource::PROVIDER_MIXPANEL)

    post_raw(source, fixture_body("mixpanel_alert"), "Authorization" => "Basic #{Base64.strict_encode64("firefight:#{source.secret_token}")}")
    assert_response :success
    assert_equal "Webhook Test", source.alerts.sole.title

    post_raw(source, fixture_body("mixpanel_alert"), "Authorization" => "Bearer #{source.secret_token}")
    assert_response :unauthorized
  end

  test "a signed PostHog delivery is one alert, and its retry with the same webhook id is not a second" do
    source = AlertSource.create!(workspace: @workspace, name: "PostHog", provider: AlertSource::PROVIDER_POSTHOG)
    body = fixture_body("posthog_insight_alert")
    headers = lambda do
      timestamp = Time.current.to_i
      signature = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", Base64.decode64(source.secret_token), "msg-1.#{timestamp}.#{body}"))
      { "webhook-id" => "msg-1", "webhook-timestamp" => timestamp.to_s, "webhook-signature" => "v1,#{signature}" }
    end

    post_raw(source, body, headers.call)
    post_raw(source, body, headers.call)

    assert_response :success
    assert_equal "msg-1", source.alerts.sole.external_id
  end

  test "a Honeycomb delivery keeps the delivery id it names in a header and never stores the shared secret" do
    source = AlertSource.create!(workspace: @workspace, name: "Honeycomb", provider: AlertSource::PROVIDER_HONEYCOMB)
    body = JSON.parse(fixture_body("honeycomb_trigger")).merge("shared_secret" => source.secret_token).to_json

    post_raw(source, body, "X-Honeycomb-Webhook-Token" => source.secret_token, "X-Honeycomb-Webhook-Delivery-ID" => "delivery-7")

    assert_response :success
    alert = source.alerts.sole
    assert_equal "delivery-7", alert.external_id
    assert_not alert.payload.key?("shared_secret")
  end

  test "a Logfire alert arrives with the secret in its address, which no log or parameter carries" do
    source = AlertSource.create!(workspace: @workspace, name: "Logfire", provider: AlertSource::PROVIDER_LOGFIRE)
    body = file_fixture("alert_providers/logfire_alert.json").read
    Net::HTTP.any_instance.expects(:start).never
    recorded = []
    subscriber = ActiveSupport::Notifications.subscribe("process_action.action_controller") { |event| recorded << event.payload }

    begin
      post "#{api_v1_alert_ingest_path(endpoint_path: source.endpoint_path)}/#{source.secret_token}",
           params: body, headers: { "Content-Type" => "application/json" }
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    assert_response :success
    assert_equal "Example alert", source.alerts.sole.title
    payload = recorded.sole
    assert_equal api_v1_alert_ingest_path(endpoint_path: source.endpoint_path), payload[:path]
    assert_not_includes payload.to_s, source.secret_token
    assert_not_includes request.filtered_path, source.secret_token
  end

  test "a Logfire source refuses its bare address, a wrong secret and a token sent as a header" do
    source = AlertSource.create!(workspace: @workspace, name: "Logfire", provider: AlertSource::PROVIDER_LOGFIRE)
    body = file_fixture("alert_providers/logfire_alert.json").read
    bare = api_v1_alert_ingest_path(endpoint_path: source.endpoint_path)

    [
      [ bare, { "Authorization" => "Bearer #{source.secret_token}" } ],
      [ "#{bare}/#{source.secret_token.reverse}", {} ]
    ].each do |path, headers|
      post path, params: body, headers: headers.merge("Content-Type" => "application/json")
      assert_response :unauthorized
    end
    assert_equal "invalid token", source.reload.last_rejection_reason
    assert_equal 0, source.alerts.count
  end

  test "a secret in the address means nothing to a source whose token travels in a header" do
    post "#{api_v1_alert_ingest_path(endpoint_path: @source.endpoint_path)}/#{@source.secret_token}",
         params: { "title" => "x" }.to_json, headers: { "Content-Type" => "application/json" }

    assert_response :unauthorized
  end
end
