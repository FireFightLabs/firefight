module AlertProviders
  # Prometheus Alertmanager's webhook receiver (prometheus.io, Configuration, webhook_config, payload version 4). Each POST
  # carries a group of alerts, and each alert in alerts[] is one Firefight alert with its own status, keyed on
  # Alertmanager's fingerprint so a resolve reaches the alert that fired. Labels and annotations follow the Prometheus
  # conventions (alertname, severity, service or job, team, environment or env, summary, description). Grafana and
  # SigNoz send the same shape. Alertmanager signs nothing, so the token travels in its http_config.
  class Alertmanager < Base
    LABEL = "Prometheus Alertmanager".freeze
    SETUP_STEPS = [
      "In alertmanager.yml, add a receiver with a webhook_configs entry whose url is this URL. Leave send_resolved on, " \
      "so alerts resolve in Firefight when they resolve in Prometheus.",
      "Under that entry's http_config, add authorization with credentials set to the token. Alertmanager sends it as " \
      "an Authorization: Bearer header.",
      "Route the alerts that should reach Firefight to that receiver, then reload Alertmanager."
    ].freeze

    def self.verify(headers:, raw_body:, source:)
      [ bearer_token(headers), headers[TOKEN_HEADER].to_s.presence, basic_password(headers) ].compact.any? do |provided|
        token_matches?(provided, source)
      end
    end

    def self.normalize(payload, source:, headers: {})
      return [] unless payload.is_a?(Hash) && payload["alerts"].is_a?(Array)

      payload["alerts"].filter_map do |alert|
        next unless alert.is_a?(Hash) && alert["labels"].is_a?(Hash)

        fields = fields_for(alert)
        item(fields, alert) if fields["fingerprint"].present? && fields["title"].present?
      end
    end

    def self.fields_for(alert)
      labels = alert["labels"]
      annotations = alert["annotations"].is_a?(Hash) ? alert["annotations"] : {}
      fingerprint = alert["fingerprint"].presence || Digest::SHA256.hexdigest(labels.sort.to_json)
      {
        "external_id" => [ fingerprint, alert["startsAt"], alert["status"] ].compact.join(":"),
        "fingerprint" => fingerprint,
        "status" => normalize_status(alert["status"]),
        "title" => labels["alertname"].presence || annotations["summary"],
        "description" => [ annotations["summary"], annotations["description"] ].compact_blank.uniq.join("\n").presence,
        "service" => labels["service"].presence || labels["job"],
        "severity_raw" => labels["severity"],
        "team" => labels["team"],
        "environment" => labels["environment"].presence || labels["env"],
        "url" => link_for(alert)
      }.compact_blank
    end

    def self.link_for(alert)
      alert["generatorURL"]
    end
  end
end
