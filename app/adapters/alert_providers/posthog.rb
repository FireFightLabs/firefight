module AlertProviders
  # PostHog's alerts, delivered through its HTTP Webhook destination (posthog.com, Alerts and the Webhook destination),
  # which signs each request to the Standard Webhooks spec with a secret the person pastes in. An insight alert posts
  # only when it fires, so each delivery is its own firing alert, told apart by the webhook id PostHog keeps across
  # retries. A logs alert posts when it fires and when it resolves, keyed on the logs alert.
  class Posthog < Base
    LABEL = "PostHog".freeze
    SECRET_PREFIX = "whsec_".freeze
    SIGNATURE_VERSION = "v1".freeze
    ID_HEADER = "webhook-id".freeze
    TIMESTAMP_HEADER = "webhook-timestamp".freeze
    SIGNATURE_HEADER = "webhook-signature".freeze
    LOGS_FIRING = "logs_alert.firing".freeze
    LOGS_RESOLVED = "logs_alert.resolved".freeze
    SETUP_STEPS = [
      "In PostHog, open the insight, click Monitor, then Alerts, and create an alert. Under Destinations choose Webhook, " \
      "paste this URL and click Add notification, then save the alert.",
      "Open Data pipelines, open the webhook destination the alert created, paste the token into its Signing secret " \
      "field and save. PostHog signs every request with it.",
      "Insight alerts only say when they fire, so each one arrives as a new alert. Logs alerts also say when they " \
      "resolve, and Firefight resolves the alert then."
    ].freeze

    # Standard Webhooks: base64 HMAC-SHA256 of "id.timestamp.body" with the decoded secret, in a list of "v1,<signature>".
    def self.verify(headers:, raw_body:, source:)
      id, timestamp, signatures = headers[ID_HEADER].to_s, headers[TIMESTAMP_HEADER].to_s, headers[SIGNATURE_HEADER].to_s
      return false if id.blank? || signatures.blank? || !fresh_timestamp?(timestamp)

      key = Base64.decode64(source.secret_token.delete_prefix(SECRET_PREFIX))
      expected = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", key, "#{id}.#{timestamp}.#{raw_body}"))
      signatures.split.any? do |entry|
        version, signature = entry.split(",", 2)
        version == SIGNATURE_VERSION && digest_matches?(signature, expected)
      end
    end

    def self.normalize(payload, source:, headers: {})
      return [] unless payload.is_a?(Hash)
      return logs_alert(payload) if [ LOGS_FIRING, LOGS_RESOLVED ].include?(payload["type"])

      insight_alert(payload, headers[ID_HEADER].to_s.presence)
    end

    def self.logs_alert(payload)
      data = payload["data"].is_a?(Hash) ? payload["data"] : {}
      return [] if data["alert_id"].blank?

      fields = {
        "external_id" => payload["id"],
        "fingerprint" => "logs_alert:#{data['alert_id']}",
        "status" => payload["type"] == LOGS_RESOLVED ? Alert::STATUS_RESOLVED : Alert::STATUS_FIRING,
        "title" => data["alert_name"].to_s,
        "description" => logs_description(data),
        "service" => data["service_names"],
        "severity_raw" => data["severity_levels"],
        "url" => data["alert_url"].presence || data["logs_url"]
      }.compact_blank
      [ item(fields, payload) ]
    end

    def self.insight_alert(payload, webhook_id)
      return [] if payload["alert_name"].blank?

      alert_id = Rack::Utils.parse_query(URI(payload["alert_url"].to_s).query.to_s)["alert_id"].presence
      fields = {
        "external_id" => webhook_id,
        "fingerprint" => [ "insight_alert", alert_id, webhook_id ].compact.join(":"),
        "status" => Alert::STATUS_FIRING,
        "title" => payload["alert_name"].to_s,
        "description" => payload["breaches"],
        "service" => payload["insight_name"],
        "url" => payload["alert_url"].presence || payload["insight_url"]
      }.compact_blank
      [ item(fields, payload) ]
    rescue URI::InvalidURIError
      []
    end

    def self.logs_description(data)
      return if data["result_count"].blank?

      sentence = "#{data['result_count']} matching logs"
      sentence += ", alerting #{data['threshold_operator']} #{data['threshold_count']}" if data["threshold_count"].present?
      sentence += " in #{data['window_minutes']} minutes" if data["window_minutes"].present?
      "#{sentence}."
    end
  end
end
