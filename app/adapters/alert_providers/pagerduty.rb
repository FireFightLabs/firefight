module AlertProviders
  # PagerDuty's v3 webhook subscriptions (PagerDuty/developer-docs, docs/webhooks/01-Overview.md). Each POST carries one
  # event. An incident triggered or reopened fires, and resolved resolves it, keyed on the incident's id so both reach one
  # alert. Every other event, such as an acknowledgement, a note or the ping a new subscription sends, is accepted and
  # ignored, since PagerDuty disables a subscription after three deliveries in a row are refused. PagerDuty's own
  # signature is made with a secret PagerDuty generates, so the source's token travels in a custom header the
  # subscription sends instead.
  class Pagerduty < Base
    INCIDENT = "incident".freeze
    FIRING_EVENTS = %w[incident.triggered incident.reopened].freeze
    RESOLVED_EVENT = "incident.resolved".freeze
    SETUP_INSTRUCTIONS = "In PagerDuty, add a generic webhook (v3) subscription with this URL and the events " \
                         "#{FIRING_EVENTS.join(', ')} and #{RESOLVED_EVENT}. Add a custom header named #{TOKEN_HEADER} holding " \
                         "the token. Firefight accepts and ignores other events.".freeze

    def self.verify(headers:, raw_body:, source:) = token_matches?(headers[TOKEN_HEADER].to_s, source)

    def self.normalize(payload, source:)
      event = payload.is_a?(Hash) && payload["event"].is_a?(Hash) ? payload["event"] : nil
      return [] unless event && alert_event?(event)

      incident = event["data"]
      fields = {
        "external_id" => event["id"].to_s,
        "fingerprint" => incident["id"].to_s,
        "status" => event["event_type"] == RESOLVED_EVENT ? Alert::STATUS_RESOLVED : Alert::STATUS_FIRING,
        "title" => incident["title"].to_s,
        "description" => description_of(incident),
        "service" => incident.dig("service", "summary"),
        "severity_raw" => incident.dig("priority", "summary").presence || incident["urgency"],
        "team" => Array(incident["teams"]).first&.dig("summary")
      }.compact_blank
      [ item(fields, payload) ]
    end

    # A well formed event that is not an incident firing or resolving.
    def self.ignored?(payload)
      event = payload.is_a?(Hash) ? payload["event"] : nil
      event.is_a?(Hash) && event["event_type"].present? && !alert_event?(event)
    end

    def self.alert_event?(event)
      (FIRING_EVENTS + [ RESOLVED_EVENT ]).include?(event["event_type"]) && event["data"].is_a?(Hash) &&
        event.dig("data", "type") == INCIDENT && event.dig("data", "id").present?
    end

    def self.description_of(incident)
      [ ("PagerDuty incident ##{incident['number']}" if incident["number"]), incident["html_url"] ].compact.join(", ").presence
    end
  end
end
