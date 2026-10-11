module AlertProviders
  # Honeycomb's Webhook recipient for triggers, with no custom payload (docs.honeycomb.io, Webhooks, and Honeycomb's
  # webhook listener example). TRIGGERED fires and OK resolves, keyed on the trigger. Honeycomb sends the recipient's
  # shared secret as is in its own header, so the token is that shared secret, and it names each delivery in a header it
  # keeps across retries.
  class Honeycomb < Base
    LABEL = "Honeycomb".freeze
    SECRET_HEADER = "X-Honeycomb-Webhook-Token".freeze
    DELIVERY_HEADER = "X-Honeycomb-Webhook-Delivery-ID".freeze
    SECRET_FIELD = "shared_secret".freeze
    TRIGGERED = "TRIGGERED".freeze
    OK = "OK".freeze
    SETUP_STEPS = [
      "In Honeycomb, open Team Settings, then Integrations, and add a recipient under Trigger, SLOs, and Anomaly " \
      "Detection Recipients. Choose Webhook as the provider.",
      "Paste this URL as the Webhook URL and the token as the Shared Secret. Leave the payload as it is and click Add.",
      "Add the recipient to each trigger that should alert. Honeycomb says when a trigger is back to OK, and Firefight " \
      "resolves the alert then."
    ].freeze

    def self.verify(headers:, raw_body:, source:) = token_matches?(headers[SECRET_HEADER].to_s, source)

    def self.normalize(payload, source:, headers: {})
      return [] unless payload.is_a?(Hash) && payload["id"].present? && [ TRIGGERED, OK ].include?(payload["status"])

      fields = {
        "external_id" => headers[DELIVERY_HEADER].to_s.presence,
        "fingerprint" => "trigger:#{payload['id']}",
        "status" => payload["status"] == OK ? Alert::STATUS_RESOLVED : Alert::STATUS_FIRING,
        "title" => payload["name"].presence || payload["summary"],
        "description" => [ payload["description"], payload["trigger_description"] ].compact_blank.join("\n").presence,
        "url" => payload["result_url"].presence || payload["trigger_url"]
      }.compact_blank
      # The standard body repeats the shared secret, which must never be stored with the alert.
      [ item(fields, payload.except(SECRET_FIELD)) ]
    end
  end
end
