require "test_helper"

class Slack::ClientTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.new(
      platform: "slack",
      platform_id: "T_TEST",
      name: "Test",
      access_token: "xoxb-test-token"
    )
  end

  test "get_user_info sends a GET request with user as a query parameter" do
    captured_request = nil
    fake_body = { ok: true, user: { id: "U123", profile: { real_name: "Test User" } } }.to_json
    fake_response = stub(body: fake_body)

    Slack::Client.stubs(:pool_request).with { |_uri, req| captured_request = req; true }.returns(fake_response)

    Slack::Client.get_user_info(workspace: @workspace, user_id: "U123")

    assert_instance_of Net::HTTP::Get, captured_request
    assert_includes captured_request.uri.query, "user=U123"
  end

  test "get_user_info raises ApiError on Slack error response" do
    fake_body = { ok: false, error: "user_not_found" }.to_json
    Slack::Client.stubs(:pool_request).returns(stub(body: fake_body))

    assert_raises(Slack::Client::ApiError) do
      Slack::Client.get_user_info(workspace: @workspace, user_id: "U_MISSING")
    end
  end
end
