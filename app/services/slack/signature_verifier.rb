module Slack
  class SignatureVerifier
    class InvalidSignatureError < StandardError; end
    class ReplayAttackError < StandardError; end

    # Verify Slack request signature
    # Raises InvalidSignatureError if signature doesn't match
    # Raises ReplayAttackError if request is too old (>5 minutes)
    def self.verify!(request)
      timestamp = request.headers["X-Slack-Request-Timestamp"]
      signature = request.headers["X-Slack-Signature"]
      body = request.raw_post

      # Check for required headers
      raise InvalidSignatureError, "Missing X-Slack-Request-Timestamp header" unless timestamp
      raise InvalidSignatureError, "Missing X-Slack-Signature header" unless signature

      # Prevent replay attacks - request must be within 5 minutes
      if Time.now.to_i - timestamp.to_i > 5.minutes.to_i
        raise ReplayAttackError, "Request timestamp is too old"
      end

      # Construct the signature base string
      sig_basestring = "v0:#{timestamp}:#{body}"

      # Compute HMAC-SHA256 signature
      signing_secret = Rails.application.credentials.slack[:signing_secret]
      computed_signature = "v0=" + OpenSSL::HMAC.hexdigest("SHA256", signing_secret, sig_basestring)

      # Compare signatures (use secure comparison to prevent timing attacks)
      unless ActiveSupport::SecurityUtils.secure_compare(computed_signature, signature)
        raise InvalidSignatureError, "Signature verification failed"
      end

      true
    end
  end
end
