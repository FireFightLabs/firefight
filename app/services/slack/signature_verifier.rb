module Slack
  # Verifies Slack request signatures using HMAC-SHA256
  # Prevents unauthorized requests and replay attacks
  class SignatureVerifier
    class InvalidSignatureError < StandardError; end
    class ReplayAttackError < StandardError; end

    # Verify Slack request signature
    # Raises InvalidSignatureError if signature doesn't match
    # Raises ReplayAttackError if request is too old
    def self.verify!(request)
      timestamp = request.headers["X-Slack-Request-Timestamp"]
      signature = request.headers["X-Slack-Signature"]
      body = request.raw_post

      # Check for required headers
      raise InvalidSignatureError, "Missing X-Slack-Request-Timestamp header" unless timestamp
      raise InvalidSignatureError, "Missing X-Slack-Signature header" unless signature

      # Prevent replay attacks - request must be within window
      if Time.now.to_i - timestamp.to_i > SlackConstants::REPLAY_ATTACK_WINDOW.to_i
        raise ReplayAttackError, "Request timestamp is too old"
      end

      # Construct the signature base string
      sig_basestring = "#{SlackConstants::SIGNATURE_VERSION}:#{timestamp}:#{body}"

      # Compute HMAC-SHA256 signature using signing secret from initializer
      computed_signature = "#{SlackConstants::SIGNATURE_VERSION}=" +
                          OpenSSL::HMAC.hexdigest("SHA256", SlackConstants::SIGNING_SECRET, sig_basestring)

      # Compare signatures (use secure comparison to prevent timing attacks)
      unless ActiveSupport::SecurityUtils.secure_compare(computed_signature, signature)
        raise InvalidSignatureError, "Signature verification failed"
      end

      true
    end
  end
end
