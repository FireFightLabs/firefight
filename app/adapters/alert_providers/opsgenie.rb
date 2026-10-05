module AlertProviders
  # Opsgenie's Webhook integration, which posts each alert action with the alert's own fields (Atlassian support,
  # Opsgenie Edge Connector alert action data). Create fires and Close resolves, keyed on the alert's id so both reach
  # one alert. Every other action, such as an acknowledgement, a note or a new tag, is accepted and ignored. Opsgenie
  # signs nothing, so the source's token travels in a custom header the integration sends.
  class Opsgenie < Base
    TOKEN_HEADER = "X-Firefight-Token".freeze
    CREATE = "Create".freeze
    CLOSE = "Close".freeze

    def self.verify(headers:, raw_body:, source:)
      provided = headers[TOKEN_HEADER].to_s
      return false if provided.blank?

      ActiveSupport::SecurityUtils.secure_compare(provided, source.secret_token)
    end

    def self.normalize(payload, source:)
      return [] unless alert_action?(payload)

      alert = payload["alert"]
      fields = {
        "external_id" => payload["action"] == CREATE ? alert["alertId"].to_s : nil,
        "fingerprint" => alert["alertId"].to_s,
        "status" => payload["action"] == CLOSE ? Alert::STATUS_RESOLVED : Alert::STATUS_FIRING,
        "title" => alert["message"].to_s.strip,
        "description" => alert["description"],
        "service" => alert["entity"],
        "severity_raw" => alert["priority"]
      }.compact_blank
      [ item(fields, payload) ]
    end

    def self.ignored?(payload)
      payload.is_a?(Hash) && payload["action"].present? && !alert_action?(payload)
    end

    def self.alert_action?(payload)
      payload.is_a?(Hash) && [ CREATE, CLOSE ].include?(payload["action"]) && payload["alert"].is_a?(Hash) &&
        payload.dig("alert", "alertId").present?
    end
  end
end
