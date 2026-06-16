require "test_helper"

class Slack::ClientTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(
      platform:     "slack",
      platform_id:  "T#{SecureRandom.hex(8)}",
      name:         "Test Workspace",
      access_token: "xoxb-test-token",
      installed_at: Time.current
    )
  end

  test "translates name_taken to ChannelExistsError" do
    stub_ok_false_response("name_taken")
    assert_raises(Slack::Client::ChannelExistsError) do
      Slack::Client.create_channel(workspace: @workspace, name: "exists")
    end
  end

  test "translates channel_not_found to ChannelNotFoundError" do
    stub_ok_false_response("channel_not_found")
    assert_raises(Slack::Client::ChannelNotFoundError) do
      Slack::Client.post_message(workspace: @workspace, channel: "Cx", text: "hi")
    end
  end

  test "translates not_in_channel to NotInChannelError" do
    stub_ok_false_response("not_in_channel")
    assert_raises(Slack::Client::NotInChannelError) do
      Slack::Client.post_message(workspace: @workspace, channel: "Cx", text: "hi")
    end
  end

  test "translates is_archived to IsArchivedError" do
    stub_ok_false_response("is_archived")
    assert_raises(Slack::Client::IsArchivedError) do
      Slack::Client.post_message(workspace: @workspace, channel: "Cx", text: "hi")
    end
  end

  test "translates restricted_action to RestrictedActionError" do
    stub_ok_false_response("restricted_action")
    assert_raises(Slack::Client::RestrictedActionError) do
      Slack::Client.invite_to_channel(workspace: @workspace, channel: "Cx", users: "U1")
    end
  end

  test "expired_trigger_id raises TriggerExpiredError without string-sniffing" do
    stub_ok_false_response("expired_trigger_id")
    assert_raises(Slack::Client::TriggerExpiredError) do
      Slack::Client.open_modal(workspace: @workspace, trigger_id: "x", view: {})
    end
  end

  test "unknown error code falls through to generic ApiError" do
    stub_ok_false_response("something_weird")
    err = assert_raises(Slack::Client::ApiError) do
      Slack::Client.post_message(workspace: @workspace, channel: "Cx", text: "hi")
    end
    assert_includes err.message, "something_weird"
  end

  test "unarchive swallows not_archived" do
    stub_ok_false_response("not_archived")
    assert_equal({ ok: true }, Slack::Client.unarchive_channel(workspace: @workspace, channel: "Cx"))
  end

  test "token_revoked raises AuthRevokedError with error_code" do
    stub_ok_false_response("token_revoked")
    err = assert_raises(Slack::Client::AuthRevokedError) do
      Slack::Client.post_message(workspace: @workspace, channel: "Cx", text: "hi")
    end
    assert_equal "token_revoked", err.error_code
  end

  test "account_inactive raises AuthRevokedError" do
    stub_ok_false_response("account_inactive")
    assert_raises(Slack::Client::AuthRevokedError) do
      Slack::Client.post_message(workspace: @workspace, channel: "Cx", text: "hi")
    end
  end

  test "invalid_auth raises AuthRevokedError" do
    stub_ok_false_response("invalid_auth")
    assert_raises(Slack::Client::AuthRevokedError) do
      Slack::Client.post_message(workspace: @workspace, channel: "Cx", text: "hi")
    end
  end

  test "429 triggers one retry honoring Retry-After then succeeds" do
    Slack::Client.stubs(:sleep)
    sequence = sequence("429-then-200")
    pool = mock_pool
    pool.expects(:request).in_sequence(sequence).returns(http_response(429, "", retry_after: "1"))
    pool.expects(:request).in_sequence(sequence).returns(http_response(200, { ok: true, ts: "1.1" }.to_json))

    body = Slack::Client.post_message(workspace: @workspace, channel: "Cx", text: "hi")
    assert_equal "1.1", body[:ts]
  end

  test "429 surfaces RateLimitedError after retry budget exhausted" do
    Slack::Client.stubs(:sleep)
    pool = mock_pool
    pool.expects(:request).twice.returns(http_response(429, "", retry_after: "2"))

    err = assert_raises(Slack::Client::RateLimitedError) do
      Slack::Client.post_message(workspace: @workspace, channel: "Cx", text: "hi")
    end
    assert_equal 2, err.retry_after
  end

  test "missing Retry-After defaults to 1 second" do
    Slack::Client.stubs(:sleep)
    pool = mock_pool
    pool.expects(:request).twice.returns(http_response(429, ""))

    err = assert_raises(Slack::Client::RateLimitedError) do
      Slack::Client.post_message(workspace: @workspace, channel: "Cx", text: "hi")
    end
    assert_equal 1, err.retry_after
  end

  test "transient 5xx retried up to MAX_RETRY_ATTEMPTS then succeeds" do
    Slack::Client.stubs(:sleep)
    sequence = sequence("5xx-recovery")
    pool = mock_pool
    pool.expects(:request).in_sequence(sequence).returns(http_response(502, ""))
    pool.expects(:request).in_sequence(sequence).returns(http_response(200, { ok: true, ts: "1.2" }.to_json))

    body = Slack::Client.post_message(workspace: @workspace, channel: "Cx", text: "hi")
    assert_equal "1.2", body[:ts]
  end

  test "sustained 5xx eventually raises ServerError" do
    Slack::Client.stubs(:sleep)
    pool = mock_pool
    pool.expects(:request).times(Slack::Client::MAX_RETRY_ATTEMPTS).returns(http_response(500, ""))

    assert_raises(Slack::Client::ServerError) do
      Slack::Client.post_message(workspace: @workspace, channel: "Cx", text: "hi")
    end
  end

  test "Net::ReadTimeout retried and eventually propagated" do
    Slack::Client.stubs(:sleep)
    pool = mock_pool
    pool.expects(:request).times(Slack::Client::MAX_RETRY_ATTEMPTS).raises(Net::ReadTimeout)

    assert_raises(Net::ReadTimeout) do
      Slack::Client.post_message(workspace: @workspace, channel: "Cx", text: "hi")
    end
  end

  test "download_file refuses non-slack.com hosts" do
    assert_raises(Slack::Client::UnsafeDownloadHost) do
      Slack::Client.download_file(workspace: @workspace, url: "https://evil.example.com/leak")
    end
  end

  test "download_file accepts files.slack.com" do
    pool = mock_pool
    pool.expects(:request).returns(http_response(200, "bytes", content_type: "image/png"))

    result = Slack::Client.download_file(workspace: @workspace, url: "https://files.slack.com/files-pri/T1/F1/x.png")
    assert_equal "bytes", result[:body]
    assert_equal "image/png", result[:content_type]
  end

  test "download_file accepts root slack.com" do
    pool = mock_pool
    pool.expects(:request).returns(http_response(200, "x"))

    Slack::Client.download_file(workspace: @workspace, url: "https://slack.com/api/x")
  end

  test "emits slack.client.call log line on success" do
    pool = mock_pool
    pool.expects(:request).returns(http_response(200, { ok: true }.to_json))

    Rails.logger.expects(:info).with(has_entries(event: "slack.client.call", endpoint: "chat.postMessage", status: 200, attempts: 1)).at_least_once

    Slack::Client.post_message(workspace: @workspace, channel: "Cx", text: "hi")
  end

  test "get_user_info sends a GET request with user as a query parameter" do
    captured_request = nil
    pool = mock_pool
    pool.expects(:request).with { |_uri, req| captured_request = req; true }
      .returns(http_response(200, { ok: true, user: { id: "U123" } }.to_json))

    Slack::Client.get_user_info(workspace: @workspace, user_id: "U123")

    assert_instance_of Net::HTTP::Get, captured_request
    assert_includes captured_request.path, "user=U123"
  end

  test "get_user_info raises ApiError on Slack error response" do
    stub_ok_false_response("user_not_found")
    assert_raises(Slack::Client::ApiError) do
      Slack::Client.get_user_info(workspace: @workspace, user_id: "U_MISSING")
    end
  end

  private

  def mock_pool
    pool = mock("http_pool")
    Slack::Client.stubs(:http_pool).returns(pool)
    pool
  end

  def stub_ok_false_response(error_code)
    pool = mock_pool
    pool.expects(:request).returns(http_response(200, { ok: false, error: error_code }.to_json))
  end

  def http_response(status, body, retry_after: nil, content_type: "application/json")
    headers = { "content-type" => content_type }
    headers["retry-after"] = retry_after if retry_after
    response = stub(code: status.to_s, body: body)
    response.stubs(:[]).returns(nil)
    headers.each { |k, v| response.stubs(:[]).with(k).returns(v) }
    response
  end
end
