require "test_helper"

class Api::V1::AppEventsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include LiveUpdatesTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @row = connect_live!(@workspace, provider: "liveapp", name: "Live app")
    @row.store_installation!("42")
    IntegrationProvider.stubs(:find).returns(nil)
    IntegrationProvider.stubs(:find).with("liveapp").returns(Struct.new(:key).new("liveapp"))
    @previous = ENV["INTEGRATION_LIVEAPP_WEBHOOK_SECRET"]
    ENV["INTEGRATION_LIVEAPP_WEBHOOK_SECRET"] = "app-secret"
  end

  teardown do
    ENV["INTEGRATION_LIVEAPP_WEBHOOK_SECRET"] = @previous
  end

  def delivery(installation, secret: "app-secret")
    body = { "installation" => { "id" => installation }, "changes" => [ change("e1", at: 1.minute.ago) ] }.to_json
    [ body, { LiveTestEvents::SIGNATURE => OpenSSL::HMAC.hexdigest("SHA256", secret, body), "Content-Type" => "application/json" } ]
  end

  test "a delivery signed with the app's secret reaches the connection made through its installation" do
    body, headers = delivery(42)

    assert_enqueued_jobs 1, only: Integrations::MapEventJob do
      post api_v1_app_events_path("liveapp"), params: body, headers: headers
    end
    assert_response :ok
    assert ResourceMap::ReceivedEvent.exists?(integration_environment: @row, provider_event_id: "e1")
  end

  test "a delivery about an installation no connection has is taken and ignored" do
    body, headers = delivery(7)

    assert_no_enqueued_jobs { post api_v1_app_events_path("liveapp"), params: body, headers: headers }
    assert_response :ok
  end

  test "a delivery the app did not sign is refused" do
    body, headers = delivery(42, secret: "wrong")

    post api_v1_app_events_path("liveapp"), params: body, headers: headers

    assert_response :unauthorized
  end

  test "a provider with no app wide events, or none set up, is not found" do
    body, headers = delivery(42)
    post api_v1_app_events_path("livetest"), params: body, headers: headers
    assert_response :not_found

    ENV["INTEGRATION_LIVEAPP_WEBHOOK_SECRET"] = nil
    post api_v1_app_events_path("liveapp"), params: body, headers: headers
    assert_response :not_found
  end
end
