module AlertProviders
  # Opsgenie's Webhook integration, which posts each alert action with the alert's own fields (Atlassian support,
  # Opsgenie Edge Connector alert action data). Create fires and Close resolves, keyed on the alert's id so both reach
  # one alert. An acknowledgement, a note and a close are also what happened to a page, which the incident the page
  # belongs to records (page_event). Every other action, such as a new tag, is accepted and ignored. Opsgenie signs
  # nothing, so the source's token travels in a custom header the integration sends. The alert action carries no
  # address of the alert's page, so these alerts have no link back.
  class Opsgenie < Base
    CREATE = "Create".freeze
    CLOSE = "Close".freeze
    ACKNOWLEDGE = "Acknowledge".freeze
    ADD_NOTE = "AddNote".freeze
    PAGE_ACTIONS = {
      ACKNOWLEDGE => Integrations::Paging::EVENT_ACKNOWLEDGED, ADD_NOTE => Integrations::Paging::EVENT_NOTED,
      CLOSE => Integrations::Paging::EVENT_RESOLVED
    }.freeze
    LABEL = "Opsgenie".freeze
    SETUP_STEPS = [
      "In Opsgenie, add a Webhook integration with this URL and send the alert description with it.",
      "Post to the URL when an alert is created, acknowledged or closed and when a note is added to it. Firefight accepts " \
      "and ignores other actions.",
      "Add a custom header named #{TOKEN_HEADER} holding the token."
    ].freeze

    def self.verify(headers:, raw_body:, source:) = token_matches?(headers[TOKEN_HEADER].to_s, source)

    def self.normalize(payload, source:, headers: {})
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

    # Opsgenie names a person by their username, which is their email. An action a rule or an integration took names none.
    def self.page_event(payload)
      kind = payload.is_a?(Hash) && PAGE_ACTIONS[payload["action"]]
      alert = kind && payload["alert"]
      return nil unless alert.is_a?(Hash) && alert["alertId"].present?

      username = alert["username"].to_s.strip
      email = username.include?("@") ? username : nil
      Integrations::Paging::Event.new(
        external_id: alert["alertId"].to_s, key: alert["alias"].presence, kind: kind, actor_name: username.presence, actor_email: email,
        by_person: email.present?, note: (alert["note"].presence if kind == Integrations::Paging::EVENT_NOTED)
      )
    end

    def self.page_key(payload) = payload.is_a?(Hash) ? payload.dig("alert", "alias").presence : nil

    def self.alert_action?(payload)
      payload.is_a?(Hash) && [ CREATE, CLOSE ].include?(payload["action"]) && payload["alert"].is_a?(Hash) &&
        payload.dig("alert", "alertId").present?
    end
  end
end
