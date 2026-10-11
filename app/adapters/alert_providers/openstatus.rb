module AlertProviders
  # OpenStatus's Webhook notification channel (openstatus.dev, Notification reference). Every POST is one monitor check,
  # error or degraded firing and recovered resolving, keyed on the monitor. OpenStatus signs nothing and sends the
  # headers set on the channel, so the token travels in one of those.
  class Openstatus < Base
    LABEL = "OpenStatus".freeze
    RECOVERED = "recovered".freeze
    STATUSES = %w[error degraded recovered].freeze
    SETUP_STEPS = [
      "In OpenStatus, open Notifications and create a notification channel of type Webhook.",
      "Paste this URL as its URL.",
      "Add a header named #{TOKEN_HEADER} holding the token.",
      "Open each monitor that should alert, select the channel on its Notifications tab and save."
    ].freeze

    def self.verify(headers:, raw_body:, source:)
      [ headers[TOKEN_HEADER].to_s.presence, bearer_token(headers) ].compact.any? { |provided| token_matches?(provided, source) }
    end

    def self.normalize(payload, source:, headers: {})
      return [] unless payload.is_a?(Hash) && STATUSES.include?(payload["status"]) && payload.dig("monitor", "id").present?

      monitor = payload["monitor"]
      status = payload["status"]
      fields = {
        "external_id" => [ monitor["id"], status, payload["cronTimestamp"] ].join(":"),
        "fingerprint" => "monitor:#{monitor['id']}",
        "status" => status == RECOVERED ? Alert::STATUS_RESOLVED : Alert::STATUS_FIRING,
        "title" => "#{monitor['name'].presence || monitor['url']} is #{status == 'degraded' ? 'degraded' : 'failing'}",
        "description" => description_of(payload),
        "service" => monitor["name"],
        "severity_raw" => status
      }.compact_blank
      [ item(fields, payload) ]
    end

    def self.description_of(payload)
      [
        payload["errorMessage"],
        ("Status code #{payload['statusCode']}" if payload["statusCode"]),
        ("Latency #{payload['latency']} ms" if payload["latency"]),
        payload.dig("monitor", "url")
      ].compact_blank.join(". ").presence
    end
  end
end
