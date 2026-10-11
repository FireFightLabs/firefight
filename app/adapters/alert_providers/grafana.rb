module AlertProviders
  # Grafana Alerting's webhook contact point (grafana.com, Configure webhook notifications), which sends Alertmanager's
  # alerts[] shape. The token arrives as the contact point's Authorization header, its Basic auth password or an extra
  # header. Grafana can also sign with an HMAC secret, the hex SHA-256 of the body, or of the timestamp, a colon and the
  # body when a timestamp header is set, so a signed request is accepted on the signature alone.
  class Grafana < Alertmanager
    LABEL = "Grafana".freeze
    SIGNATURE_HEADER = "X-Grafana-Alerting-Signature".freeze
    TIMESTAMP_HEADER = "X-Grafana-Alerting-Timestamp".freeze
    SETUP_STEPS = [
      "In Grafana, open Alerting, then Contact points, and add a contact point with the Webhook integration.",
      "Paste this URL as its URL.",
      "Under Optional Webhook settings, paste the token into Authorization Header Credentials and leave the scheme as " \
      "Bearer. To sign requests instead, paste the token as the HMAC secret, keep the header #{SIGNATURE_HEADER} and set " \
      "the timestamp header to #{TIMESTAMP_HEADER}.",
      "Leave Disable resolved message off, so alerts resolve in Firefight when they resolve in Grafana. Save the " \
      "contact point and use it in a notification policy."
    ].freeze

    def self.verify(headers:, raw_body:, source:)
      signature = headers[SIGNATURE_HEADER].to_s
      return signed?(signature, headers[TIMESTAMP_HEADER].to_s, raw_body, source) if signature.present?

      super
    end

    def self.signed?(signature, timestamp, raw_body, source)
      return digest_matches?(signature, hmac_hex(source.secret_token, raw_body)) if timestamp.blank?

      fresh_timestamp?(timestamp) && digest_matches?(signature, hmac_hex(source.secret_token, "#{timestamp}:#{raw_body}"))
    end

    # The panel or dashboard the rule watches when Grafana knows it, else the rule itself.
    def self.link_for(alert)
      alert["panelURL"].presence || alert["dashboardURL"].presence || alert["generatorURL"]
    end
  end
end
