module AlertProviders
  # Axiom's Custom webhook notifier with its default body (axiom.co, Custom webhook notifier). Open fires and Closed
  # resolves, keyed on the monitor and, for a monitor that notifies by group, the group's values. A match monitor only
  # ever opens. Axiom signs nothing, so the token travels in a header set on the notifier.
  class Axiom < Base
    LABEL = "Axiom".freeze
    OPEN = "Open".freeze
    CLOSED = "Closed".freeze
    SETUP_STEPS = [
      "In Axiom, open Monitors, then Manage notifiers, and create a notifier of type Custom webhook.",
      "Paste this URL as the Webhook URL and keep the default body.",
      "Add a header named #{TOKEN_HEADER} holding the token, then create the notifier.",
      "Choose the notifier on each monitor that should alert. A threshold monitor says when it closes, and Firefight " \
      "resolves the alert then."
    ].freeze

    def self.verify(headers:, raw_body:, source:)
      [ headers[TOKEN_HEADER].to_s.presence, bearer_token(headers) ].compact.any? { |provided| token_matches?(provided, source) }
    end

    def self.normalize(payload, source:, headers: {})
      event = payload.is_a?(Hash) ? payload["event"] : nil
      return [] unless event.is_a?(Hash) && event["monitorID"].present? && [ OPEN, CLOSED ].include?(payload["action"])

      group = Array(event["groupValues"]).join(",")
      fields = {
        "external_id" => [ event["monitorID"], payload["action"], event["timestamp"], group ].join(":"),
        "fingerprint" => [ "monitor", event["monitorID"], group.presence ].compact.join(":"),
        "status" => payload["action"] == CLOSED ? Alert::STATUS_RESOLVED : Alert::STATUS_FIRING,
        "title" => event["title"].presence || "Axiom monitor #{event['monitorID']}",
        "description" => [ event["body"], event["description"] ].compact_blank.join("\n").presence
      }.compact_blank
      [ item(fields, payload) ]
    end
  end
end
