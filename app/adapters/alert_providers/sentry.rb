module AlertProviders
  # Sentry's Integration Platform webhooks from an internal integration (docs.sentry.io, Integration Platform, Webhooks,
  # Issue Alerts, Metric Alerts and Issues). Sentry signs every body with the integration's client secret, a secret Sentry
  # makes, so the person pastes it into the source. An issue alert fires, keyed on its issue, and the issue resolving in
  # Sentry resolves it. A metric alert fires when critical or warning and resolves when resolved, keyed on the metric
  # alert. Every other delivery, such as the installation or an issue being created or assigned, is accepted and ignored.
  class Sentry < Base
    LABEL = "Sentry".freeze
    SECRET_FROM_PROVIDER = true
    SIGNATURE_HEADER = "Sentry-Hook-Signature".freeze
    RESOLVED = "resolved".freeze
    METRIC_FIRING = %w[critical warning].freeze
    # The project slug in an event's API address, /api/0/projects/<organization>/<project>/events/<id>/.
    PROJECT_IN_EVENT_URL = %r{/projects/[^/]+/([^/]+)/events/}
    SETUP_STEPS = [
      "In Sentry, open Settings, then Developer Settings, and create a new internal integration.",
      "Paste this URL as its Webhook URL and turn on Alert Rule Action. To have alerts resolve when their issue resolves " \
      "in Sentry, also give it Issue & Event read permission and subscribe it to issue webhooks.",
      "Save the integration, then copy its Client Secret and paste it below. Sentry signs every request with it.",
      "In each alert that should reach Firefight, add the action that sends a notification via the integration. Metric " \
      "alerts also say when they resolve."
    ].freeze

    def self.verify(headers:, raw_body:, source:)
      digest_matches?(headers[SIGNATURE_HEADER].to_s, hmac_hex(source.secret_token, raw_body))
    end

    def self.normalize(payload, source:, headers: {})
      data = payload.is_a?(Hash) ? payload["data"] : nil
      return [] unless data.is_a?(Hash)

      fields = if data["event"].is_a?(Hash) && data["event"]["issue_id"].present? then issue_alert(data)
      elsif data["metric_alert"].is_a?(Hash) && data["metric_alert"]["id"].present? then metric_alert(payload["action"], data)
      elsif data["issue"].is_a?(Hash) && payload["action"] == RESOLVED then issue_resolved(data["issue"])
      end
      fields ? [ item(fields.compact_blank, payload) ] : []
    end

    # A delivery in Sentry's envelope that is not an alert firing or resolving.
    def self.ignored?(payload)
      payload.is_a?(Hash) && payload["action"].present? && payload["installation"].is_a?(Hash) && normalize(payload, source: nil).empty?
    end

    def self.issue_alert(data)
      event = data["event"]
      {
        "external_id" => "event:#{event['event_id']}:#{data['triggered_rule']}",
        "fingerprint" => "issue:#{event['issue_id']}",
        "status" => Alert::STATUS_FIRING,
        "title" => event["title"].presence || data["triggered_rule"],
        "description" => [ event.dig("metadata", "value"), event["culprit"] ].compact_blank.join("\n").presence,
        "service" => event["url"].to_s[PROJECT_IN_EVENT_URL, 1],
        "severity_raw" => event["level"],
        "environment" => event["environment"].presence || tag(event, "environment"),
        "url" => event["web_url"]
      }
    end

    def self.metric_alert(action, data)
      return unless (METRIC_FIRING + [ RESOLVED ]).include?(action)

      metric = data["metric_alert"]
      rule = metric["alert_rule"].is_a?(Hash) ? metric["alert_rule"] : {}
      {
        "external_id" => "metric:#{metric['id']}:#{action}",
        "fingerprint" => "metric:#{metric['id']}",
        "status" => action == RESOLVED ? Alert::STATUS_RESOLVED : Alert::STATUS_FIRING,
        "title" => rule["name"].presence || data["description_title"],
        "description" => data["description_text"].to_s.gsub("\\n", "\n").presence,
        "service" => Array(metric["projects"]).first || Array(rule["projects"]).first,
        "severity_raw" => action == RESOLVED ? nil : action,
        "environment" => rule["environment"],
        "url" => data["web_url"]
      }
    end

    def self.issue_resolved(issue)
      return if issue["id"].blank?

      { "fingerprint" => "issue:#{issue['id']}", "status" => Alert::STATUS_RESOLVED, "title" => issue["title"], "url" => issue["web_url"] }
    end

    def self.tag(event, key)
      Array(event["tags"]).find { |pair| pair.is_a?(Array) && pair.first == key }&.second
    end
  end
end
