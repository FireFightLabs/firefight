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
         params: { "title" => "x" * (Api::V1::AlertsController::MAX_PAYLOAD_BYTES + 1) }.to_json,
         headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{@source.secret_token}" }

    assert_response :content_too_large
    assert_equal "payload too large", @source.reload.last_rejection_reason
    assert_equal 0, @source.alerts.count
  end

  test "oversized batches are rejected" do
    items = Array.new(Api::V1::AlertsController::MAX_BATCH_ITEMS + 1) { |i| AlertProviders::Base.item({ "title" => "a#{i}" }, {}) }
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

  # With Content-Type: application/json, Rails' params middleware already
  # rejects malformed bodies with a 400 before the controller runs. This covers
  # the non-JSON content type path where the controller parses raw_post itself.
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

  test "rate limit returns 429 before verification work" do
    Rails.cache.stubs(:increment).returns(AlertSource::DEFAULT_RATE_LIMIT_PER_MINUTE + 1)

    post_alert({ "title" => "x" })

    assert_response :too_many_requests
    assert_equal 0, @source.alerts.count
  end
end
