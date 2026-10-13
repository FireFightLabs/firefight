# A workflow's own address, which an inbound webhook trigger starts it at: POST to it with a JSON body, signed the way
# Firefight signs its outbound webhooks (v1, an HMAC-SHA256 of "v1:<timestamp>:<body>" keyed by the workflow's secret,
# sent with the timestamp it signed). The address names the workflow by an unguessable token. The secret is never
# stored: it is worked out from the token with a key only Firefight holds, so replacing the address replaces the
# secret too, and showing it is reading it again.
module Workflow::Hook
  extend ActiveSupport::Concern

  # The scheme Firefight's outbound webhooks sign with (Webhooks::DeliveryService), so one way of checking serves both.
  SIGNATURE_SCHEME = "v1".freeze
  SIGNATURE_HEADER = "X-Firefight-Signature".freeze
  TIMESTAMP_HEADER = "X-Firefight-Timestamp".freeze
  DELIVERY_HEADER = "X-Firefight-Delivery".freeze
  # A signature older or newer than this is refused, so a captured delivery cannot be sent again later.
  FRESH_FOR = 5.minutes
  KEY_SALT = "workflow inbound webhooks".freeze

  included do
    has_secure_token :hook_token, length: 32
  end

  class_methods do
    def hook_key = Rails.application.key_generator.generate_key(KEY_SALT, 32)
  end

  def hook_secret = OpenSSL::HMAC.hexdigest("SHA256", self.class.hook_key, "#{id}:#{hook_token}")

  def hook_url = AppUrl.absolute(Rails.application.routes.url_helpers.api_v1_workflow_hook_path(hook_token))

  # Whether a delivery was signed with this workflow's secret within the last few minutes.
  def hook_signed?(raw_body, timestamp:, signature:, now: Time.current)
    at = Time.iso8601(timestamp.to_s)
    return false unless (at - now).abs <= FRESH_FOR

    expected = "#{SIGNATURE_SCHEME}=#{OpenSSL::HMAC.hexdigest('SHA256', hook_secret, "#{SIGNATURE_SCHEME}:#{timestamp}:#{raw_body}")}"
    ActiveSupport::SecurityUtils.secure_compare(signature.to_s, expected)
  rescue ArgumentError
    false
  end

  # A new address and so a new secret. The old one stops working at once.
  def replace_hook!
    regenerate_hook_token
  end

  # Whether its live version starts on its own address.
  def hooked? = enabled? && live_version&.trigger.to_h[Workflow::Trigger::KEY_KIND] == Workflow::Trigger::KIND_INBOUND_WEBHOOK
end
