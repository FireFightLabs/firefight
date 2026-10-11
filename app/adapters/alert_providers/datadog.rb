module AlertProviders
  # Datadog's Webhooks integration (docs.datadoghq.com, Webhooks), whose body is a template the person writes. Its
  # default body carries neither the transition nor anything tying a recovery to its trigger, so setup hands over
  # TEMPLATE, built from Datadog's documented variables. A recovery resolves, every other transition fires, keyed on the
  # alert cycle so a recovery reaches the trigger it ends. Datadog signs nothing, so the token travels in a custom header.
  class Datadog < Base
    LABEL = "Datadog".freeze
    RECOVERED = "Recovered".freeze
    TEMPLATE = <<~JSON.freeze
      {
        "id": "$ID",
        "alert_cycle_key": "$ALERT_CYCLE_KEY",
        "aggregation_key": "$AGGREG_KEY",
        "monitor_id": "$ALERT_ID",
        "transition": "$ALERT_TRANSITION",
        "title": "$EVENT_TITLE",
        "message": "$TEXT_ONLY_MSG",
        "priority": "$ALERT_PRIORITY",
        "service": "$TAGS[service]",
        "environment": "$TAGS[env]",
        "team": "$TAGS[team]",
        "link": "$LINK"
      }
    JSON
    SETUP_STEPS = [
      "In Datadog, open the Webhooks integration and add a webhook. Name it, such as firefight, and paste this URL as its URL.",
      "Replace its payload with the template below, and leave Encode as form off.",
      "Under Custom Headers, enter {\"#{TOKEN_HEADER}\": \"\"} with the token between the empty quotes, and save.",
      "Mention @webhook-firefight, or the name you chose, in each monitor's message. Datadog sends the recovery too, " \
      "and Firefight resolves the alert then."
    ].freeze

    def self.verify(headers:, raw_body:, source:)
      [ headers[TOKEN_HEADER].to_s.presence, bearer_token(headers) ].compact.any? { |provided| token_matches?(provided, source) }
    end

    def self.normalize(payload, source:, headers: {})
      return [] unless payload.is_a?(Hash) && payload["transition"].present?

      cycle = payload["alert_cycle_key"].presence || payload["aggregation_key"].presence
      return [] unless cycle

      fields = {
        "external_id" => payload["id"],
        "fingerprint" => "cycle:#{cycle}",
        "status" => payload["transition"] == RECOVERED ? Alert::STATUS_RESOLVED : Alert::STATUS_FIRING,
        "title" => title_of(payload),
        "description" => payload["message"],
        "service" => payload["service"],
        "severity_raw" => payload["priority"],
        "team" => payload["team"],
        "environment" => payload["environment"],
        "url" => payload["link"]
      }.compact_blank
      [ item(fields, payload) ]
    end

    # Datadog leads the event title with the transition and scope, such as "[Triggered on {host:a}] High CPU", which
    # would make a recovery's title differ from its trigger's.
    def self.title_of(payload)
      payload["title"].to_s.sub(/\A\[[^\]]*\]\s*/, "").presence || "Datadog monitor #{payload['monitor_id']}"
    end
  end
end
