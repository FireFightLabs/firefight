module AlertProviders
  # Better Stack's incident webhook (betterstack.com, Uptime, Webhooks), one incident a POST in its JSON:API shape. An
  # incident fires until resolved_at is set, keyed on the incident's id. A comment is accepted and ignored. Better Stack
  # signs nothing, so the token travels in a header set on the webhook.
  class BetterStack < Base
    LABEL = "Better Stack".freeze
    INCIDENT = "incident".freeze
    COMMENT_EVENT = "comment".freeze
    SETUP_STEPS = [
      "In Better Stack, open Incidents, then Integrations, and under Exporting data configure Outgoing webhooks. Add an " \
      "Incident webhook.",
      "Paste this URL as the Webhook URL.",
      "Send it on incident started, resolved and reopened.",
      "Customize the request template and add a header named #{TOKEN_HEADER} holding the token. Leave the request body as it is."
    ].freeze

    def self.verify(headers:, raw_body:, source:)
      [ headers[TOKEN_HEADER].to_s.presence, bearer_token(headers), basic_password(headers) ].compact.any? do |provided|
        token_matches?(provided, source)
      end
    end

    def self.normalize(payload, source:, headers: {})
      return [] unless incident?(payload) && payload["event"] != COMMENT_EVENT

      incident = payload["data"]
      attributes = incident["attributes"].is_a?(Hash) ? incident["attributes"] : {}
      resolved = attributes["resolved_at"].present?
      fields = {
        "external_id" => [ incident["id"], attributes["started_at"], (resolved ? attributes["resolved_at"] : nil) ].compact.join(":"),
        "fingerprint" => "incident:#{incident['id']}",
        "status" => resolved ? Alert::STATUS_RESOLVED : Alert::STATUS_FIRING,
        "title" => attributes["name"].presence || "Better Stack incident #{incident['id']}",
        "description" => [ attributes["cause"], attributes["url"] ].compact_blank.join(". ").presence
      }.compact_blank
      [ item(fields, payload) ]
    end

    def self.ignored?(payload)
      incident?(payload) && payload["event"] == COMMENT_EVENT
    end

    def self.incident?(payload)
      payload.is_a?(Hash) && payload["data"].is_a?(Hash) && payload.dig("data", "type") == INCIDENT && payload.dig("data", "id").present?
    end
  end
end
