module Slack
  class SignatureVerifier
    class InvalidSignatureError < StandardError; end
    class ReplayAttackError < StandardError; end

    def self.verify!(request)
      timestamp = request.headers["X-Slack-Request-Timestamp"]
      signature = request.headers["X-Slack-Signature"]
      body = request.raw_post

      raise InvalidSignatureError, "Missing X-Slack-Request-Timestamp header" unless timestamp
      raise InvalidSignatureError, "Missing X-Slack-Signature header" unless signature

      # A captured request replayed outside the window is refused.
      if Time.now.to_i - timestamp.to_i > SlackConstants::REPLAY_ATTACK_WINDOW.to_i
        raise ReplayAttackError, "Request timestamp is too old"
      end

      sig_basestring = "#{SlackConstants::SIGNATURE_VERSION}:#{timestamp}:#{body}"

      computed_signature = "#{SlackConstants::SIGNATURE_VERSION}=" +
                          OpenSSL::HMAC.hexdigest("SHA256", SlackConstants::SIGNING_SECRET, sig_basestring)

      # Constant-time compare, so a wrong signature leaks nothing through timing.
      unless ActiveSupport::SecurityUtils.secure_compare(computed_signature, signature)
        raise InvalidSignatureError, "Signature verification failed"
      end

      true
    end
  end
end
