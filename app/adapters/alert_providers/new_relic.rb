module AlertProviders
  # New Relic's alert workflows posting to a Webhook destination with the default payload template (docs.newrelic.com,
  # Notification integrations, Webhook). Each POST is one issue, CLOSED resolving and every other state firing, keyed on
  # the issue's id. The token arrives as the destination's bearer token.
  class NewRelic < Base
    LABEL = "New Relic".freeze
    CLOSED = "CLOSED".freeze
    SETUP_STEPS = [
      "In New Relic, open Alerts, then Destinations, and add a Webhook destination. Paste this URL as the Endpoint URL.",
      "Turn on Use authorization, choose Bearer Token and paste the token. Save the destination.",
      "In Alerts, then Workflows, add or edit a workflow and notify the Webhook destination. Keep the default payload " \
      "template, and notify when issues are activated and closed, so alerts resolve in Firefight when New Relic closes them."
    ].freeze

    def self.verify(headers:, raw_body:, source:)
      [ bearer_token(headers), headers[TOKEN_HEADER].to_s.presence ].compact.any? { |provided| token_matches?(provided, source) }
    end

    def self.normalize(payload, source:, headers: {})
      return [] unless payload.is_a?(Hash) && payload["id"].present? && payload["state"].present?

      fields = {
        "external_id" => [ payload["id"], payload["state"], payload["updatedAt"] ].compact.join(":"),
        "fingerprint" => "issue:#{payload['id']}",
        "status" => payload["state"].to_s.upcase == CLOSED ? Alert::STATUS_RESOLVED : Alert::STATUS_FIRING,
        "title" => payload["title"].to_s,
        "description" => description_of(payload),
        "service" => Array(payload["impactedEntities"]).first,
        "severity_raw" => payload["priority"],
        "url" => payload["issueUrl"]
      }.compact_blank
      [ item(fields, payload) ]
    end

    def self.description_of(payload)
      policies = Array(payload["alertPolicyNames"]).join(", ")
      conditions = Array(payload["alertConditionNames"]).join(", ")
      [ ("Policy #{policies}" if policies.present?), ("condition #{conditions}" if conditions.present?) ].compact.join(", ").presence
    end
  end
end
