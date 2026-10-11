module AlertProviders
  # PagerDuty's v3 webhook subscriptions (PagerDuty/developer-docs, docs/webhooks/01-Overview.md). Each POST carries one
  # event. An incident triggered or reopened fires, and resolved resolves it, keyed on the incident's id so both reach one
  # alert. An acknowledgement, an escalation, a note and a resolve are also what happened to a page, which the incident
  # the page belongs to records (page_event). Every other event, such as the ping a new subscription sends, is accepted
  # and ignored, since PagerDuty disables a subscription after three deliveries in a row are refused. PagerDuty's own
  # signature is made with a secret PagerDuty generates, so the source's token travels in a custom header the
  # subscription sends instead.
  class Pagerduty < Base
    INCIDENT = "incident".freeze
    NOTE = "incident_note".freeze
    FIRING_EVENTS = %w[incident.triggered incident.reopened].freeze
    RESOLVED_EVENT = "incident.resolved".freeze
    ACKNOWLEDGED_EVENT = "incident.acknowledged".freeze
    ESCALATED_EVENT = "incident.escalated".freeze
    ANNOTATED_EVENT = "incident.annotated".freeze
    PAGE_EVENTS = {
      ACKNOWLEDGED_EVENT => Integrations::Paging::EVENT_ACKNOWLEDGED, ESCALATED_EVENT => Integrations::Paging::EVENT_ESCALATED,
      ANNOTATED_EVENT => Integrations::Paging::EVENT_NOTED, RESOLVED_EVENT => Integrations::Paging::EVENT_RESOLVED
    }.freeze
    # Who did it, when a person did. Automation, such as a monitor resolving its own incident, is a service or nobody.
    PERSON = "user_reference".freeze
    LABEL = "PagerDuty".freeze
    SETUP_STEPS = [
      "In PagerDuty, add a generic webhook (v3) subscription with this URL.",
      "Subscribe it to the events #{FIRING_EVENTS.join(', ')}, #{RESOLVED_EVENT}, #{ACKNOWLEDGED_EVENT}, #{ESCALATED_EVENT} and " \
      "#{ANNOTATED_EVENT}. Firefight accepts and ignores other events.",
      "Add a custom header named #{TOKEN_HEADER} holding the token."
    ].freeze

    def self.verify(headers:, raw_body:, source:) = token_matches?(headers[TOKEN_HEADER].to_s, source)

    def self.normalize(payload, source:, headers: {})
      event = event_of(payload)
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
        "team" => Array(incident["teams"]).first&.dig("summary"),
        "url" => incident["html_url"]
      }.compact_blank
      [ item(fields, payload) ]
    end

    # A well formed event that is not an incident firing or resolving.
    def self.ignored?(payload)
      event = event_of(payload)
      event.present? && event["event_type"].present? && !alert_event?(event)
    end

    # PagerDuty names who did it but not their email, so its people are named on the timeline and never taken for a member.
    def self.page_event(payload)
      event = event_of(payload)
      kind = event && PAGE_EVENTS[event["event_type"]]
      data = event&.dig("data")
      return nil unless kind && data.is_a?(Hash)

      note = data["type"] == NOTE
      incident = note ? data["incident"] : data
      return nil unless incident.is_a?(Hash) && incident["id"].present?

      agent = event["agent"].is_a?(Hash) ? event["agent"] : {}
      Integrations::Paging::Event.new(
        id: event["id"].presence, external_id: incident["id"].to_s, key: (data["incident_key"].presence unless note), kind: kind,
        actor_name: agent["summary"].presence, by_person: agent["type"] == PERSON, note: note ? data["content"] : escalated_to(data, kind)
      )
    end

    def self.page_key(payload) = event_of(payload)&.dig("data", "incident_key").presence

    def self.event_of(payload) = payload.is_a?(Hash) && payload["event"].is_a?(Hash) ? payload["event"] : nil

    def self.alert_event?(event)
      (FIRING_EVENTS + [ RESOLVED_EVENT ]).include?(event["event_type"]) && event["data"].is_a?(Hash) &&
        event.dig("data", "type") == INCIDENT && event.dig("data", "id").present?
    end

    def self.escalated_to(incident, kind)
      return nil unless kind == Integrations::Paging::EVENT_ESCALATED

      names = Array(incident["assignees"]).filter_map { |assignee| assignee["summary"].presence }
      "To #{names.to_sentence}." if names.any?
    end

    def self.description_of(incident)
      [ ("PagerDuty incident ##{incident['number']}" if incident["number"]), incident["html_url"] ].compact.join(", ").presence
    end
  end
end
