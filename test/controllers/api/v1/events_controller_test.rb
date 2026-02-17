require "test_helper"

class Api::V1::EventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Slack::SignatureVerifier.stubs(:verify!).returns(true)
  end

  test "responds to url_verification challenge" do
    post api_v1_events_path, params: { type: "url_verification", challenge: "test_challenge_token" }, as: :json

    assert_response :ok
    assert_equal "test_challenge_token", JSON.parse(response.body)["challenge"]
  end

  test "enqueues ProcessEventJob for event_callback" do
    payload = {
      type: "event_callback",
      team_id: "T12345",
      event: {
        type: "reaction_added",
        user: "U12345",
        reaction: "boom",
        item: { type: "message", channel: "C12345", ts: "1234567890.123456" }
      }
    }

    assert_enqueued_with(job: ProcessEventJob) do
      post api_v1_events_path, params: payload, as: :json
    end

    assert_response :ok
  end

  test "returns ok for unknown event types" do
    payload = {
      type: "event_callback",
      team_id: "T12345",
      event: { type: "message", text: "hello" }
    }

    post api_v1_events_path, params: payload, as: :json

    assert_response :ok
  end
end
