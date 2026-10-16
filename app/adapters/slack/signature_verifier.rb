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

      if (Time.now.to_i - timestamp.to_i).abs > SlackConstants::REPLAY_ATTACK_WINDOW.to_i
        raise ReplayAttackError, "Request timestamp is outside the replay window"
      end

      sig_basestring = "#{SlackConstants::SIGNATURE_VERSION}:#{timestamp}:#{body}"

      computed_signature = "#{SlackConstants::SIGNATURE_VERSION}=" +
                          OpenSSL::HMAC.hexdigest("SHA256", SlackConstants::SIGNING_SECRET, sig_basestring)

      unless ActiveSupport::SecurityUtils.secure_compare(computed_signature, signature)
        raise InvalidSignatureError, "Signature verification failed"
      end

      true
    end
  end
end
