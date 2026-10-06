require "test_helper"

class Api::V1::MapEventsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include LiveUpdatesTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @row = connect_live!(@workspace)
    @row.give_map_events_token!
    @row.save_map_events_secret!("whsec")
  end

  test "a delivery signed with the connection's secret is kept and queues a re-read" do
    body, headers = live_delivery([ change("e1", at: 1.minute.ago) ], secret: "whsec")

    assert_enqueued_jobs 1, only: Integrations::MapEventJob do
      post api_v1_map_events_path(@row.map_events_token), params: body, headers: headers
    end
    assert_response :ok
    assert ResourceMap::ReceivedEvent.exists?(integration_environment: @row, provider_event_id: "e1")
  end

  test "a delivery whose signature fails is refused, logged and kept nowhere" do
    body, headers = live_delivery([ change("e1", at: 1.minute.ago) ], secret: "someone else's")
    Rails.logger.expects(:warn).with { |line| line.include?("map_events.signature_refused") }

    assert_no_enqueued_jobs do
      post api_v1_map_events_path(@row.map_events_token), params: body, headers: headers
    end
    assert_response :unauthorized
    assert_not ResourceMap::ReceivedEvent.exists?(integration_environment: @row)
  end

  test "nothing is accepted before a secret is saved" do
    @row.update!(map_events_secret: nil)
    body, headers = live_delivery([ change("e1", at: 1.minute.ago) ], secret: "")

    post api_v1_map_events_path(@row.map_events_token), params: body, headers: headers

    assert_response :unauthorized
  end

  test "an unknown address, a switched off connection or a provider that sends no changes is not found" do
    body, headers = live_delivery([ change("e1", at: 1.minute.ago) ], secret: "whsec")
    post api_v1_map_events_path("nope"), params: body, headers: headers
    assert_response :not_found

    @row.integration.update!(disabled_at: Time.current)
    post api_v1_map_events_path(@row.map_events_token), params: body, headers: headers
    assert_response :not_found

    @row.integration.update!(disabled_at: nil, provider: "notion")
    post api_v1_map_events_path(@row.map_events_token), params: body, headers: headers
    assert_response :not_found
  end

  test "a delivery over a megabyte is refused before it is read" do
    body = { "changes" => [], "padding" => "x" * 1.megabyte }.to_json

    post api_v1_map_events_path(@row.map_events_token), params: body, headers: { "Content-Type" => "application/json" }

    assert_response :content_too_large
  end

  test "a body that is not JSON is a bad request" do
    body = "not json"
    headers = { LiveTestEvents::SIGNATURE => OpenSSL::HMAC.hexdigest("SHA256", "whsec", body), "Content-Type" => "text/plain" }

    post api_v1_map_events_path(@row.map_events_token), params: body, headers: headers

    assert_response :bad_request
  end

  test "an address sent too many deliveries in a minute is told to slow down" do
    ActiveSupport::Cache::NullStore.any_instance.stubs(:increment).returns(601)
    body, headers = live_delivery([ change("e1", at: 1.minute.ago) ], secret: "whsec")

    post api_v1_map_events_path(@row.map_events_token), params: body, headers: headers

    assert_response :too_many_requests
  end
end
