module AlertProviders
  # Opsgenie's Webhook integration, which posts each alert action with the alert's own fields (Atlassian support,
  # Opsgenie Edge Connector alert action data). Create fires and Close resolves, keyed on the alert's id so both reach
  # one alert. Every other action, such as an acknowledgement, a note or a new tag, is accepted and ignored. Opsgenie
  # signs nothing, so the source's token travels in a custom header the integration sends.
  class Opsgenie < Base
    CREATE = "Create".freeze
    CLOSE = "Close".freeze
    SETUP_INSTRUCTIONS = "In Opsgenie, add a Webhook integration with this URL, send the alert description with it, and post to " \
                         "the URL when an alert is created and when it is closed. Add a custom header named #{TOKEN_HEADER} " \
                         "holding the token. Firefight accepts and ignores other actions.".freeze

    def self.verify(headers:, raw_body:, source:) = token_matches?(headers[TOKEN_HEADER].to_s, source)

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
