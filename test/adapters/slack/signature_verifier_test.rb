require "test_helper"

class Slack::SignatureVerifierTest < ActiveSupport::TestCase
  setup do
    @valid_body = "token=test&team_id=T12345678&text=hello"
    @valid_timestamp = Time.now.to_i
    @valid_signature = generate_valid_signature(@valid_body, @valid_timestamp)
  end

  test "verify! returns true for valid signature" do
    request = mock_request(
      body: @valid_body,
      timestamp: @valid_timestamp,
      signature: @valid_signature
    )

    assert Slack::SignatureVerifier.verify!(request)
  end

  test "verify! raises InvalidSignatureError when signature is missing" do
    request = mock_request(
      body: @valid_body,
      timestamp: @valid_timestamp,
      signature: nil
    )

    assert_raises(Slack::SignatureVerifier::InvalidSignatureError) do
      Slack::SignatureVerifier.verify!(request)
    end
  end

  test "verify! raises InvalidSignatureError when timestamp is missing" do
    request = mock_request(
      body: @valid_body,
      timestamp: nil,
      signature: @valid_signature
    )

    assert_raises(Slack::SignatureVerifier::InvalidSignatureError) do
      Slack::SignatureVerifier.verify!(request)
    end
  end

  test "verify! raises InvalidSignatureError when signature is invalid" do
    request = mock_request(
      body: @valid_body,
      timestamp: @valid_timestamp,
      signature: "v0=invalid_signature"
    )

    assert_raises(Slack::SignatureVerifier::InvalidSignatureError) do
      Slack::SignatureVerifier.verify!(request)
    end
  end

  test "verify! raises InvalidSignatureError when body is tampered" do
    tampered_body = "token=test&team_id=T99999999&text=hacked"
    request = mock_request(
      body: tampered_body,
      timestamp: @valid_timestamp,
      signature: @valid_signature
    )

    assert_raises(Slack::SignatureVerifier::InvalidSignatureError) do
      Slack::SignatureVerifier.verify!(request)
    end
  end

  test "verify! raises ReplayAttackError when timestamp is too old" do
    old_timestamp = (Time.now - SlackConstants::REPLAY_ATTACK_WINDOW - 1.minute).to_i
    old_signature = generate_valid_signature(@valid_body, old_timestamp)

    request = mock_request(
      body: @valid_body,
      timestamp: old_timestamp,
      signature: old_signature
    )

    assert_raises(Slack::SignatureVerifier::ReplayAttackError) do
      Slack::SignatureVerifier.verify!(request)
    end
  end

  test "verify! accepts requests within replay attack window" do
    recent_timestamp = (Time.now - SlackConstants::REPLAY_ATTACK_WINDOW + 1.minute).to_i
    recent_signature = generate_valid_signature(@valid_body, recent_timestamp)

    request = mock_request(
      body: @valid_body,
      timestamp: recent_timestamp,
      signature: recent_signature
    )

    assert Slack::SignatureVerifier.verify!(request)
  end

  private

  def generate_valid_signature(body, timestamp)
    sig_basestring = "#{SlackConstants::SIGNATURE_VERSION}:#{timestamp}:#{body}"
    "#{SlackConstants::SIGNATURE_VERSION}=" +
      OpenSSL::HMAC.hexdigest("SHA256", SlackConstants::SIGNING_SECRET, sig_basestring)
  end

  def mock_request(body:, timestamp:, signature:)
    request = Object.new
    request.define_singleton_method(:raw_post) { body }
    request.define_singleton_method(:headers) do
      {
        "X-Slack-Request-Timestamp" => timestamp&.to_s,
        "X-Slack-Signature" => signature
      }
    end
    request
  end
end
