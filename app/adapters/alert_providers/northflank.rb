module AlertProviders
  # Northflank notification-integration webhooks. Payload shape:
  #   { "event" => "container:crash", "data" => { "service" => {...}, "project" => {...}, ... } }
  # The integration secret arrives in X-Northflank-Notification-Integration-Token.
  # Northflank events are one-shot (no resolved counterpart), so alerts are
  # always firing; fingerprinting on event+project+service collapses a
  # crash-looping container into one alert.
  class Northflank < Base
    TOKEN_HEADER = "X-Northflank-Notification-Integration-Token".freeze

    def self.verify(headers:, raw_body:, source:)
      provided = headers[TOKEN_HEADER].to_s
      return false if provided.blank?

      ActiveSupport::SecurityUtils.secure_compare(provided, source.secret_token)
    end

    def self.normalize(payload, source:)
      return [] unless payload.is_a?(Hash) && payload["event"].present?

      event = payload["event"].to_s
      data = payload["data"].is_a?(Hash) ? payload["data"] : {}
      service = data.dig("service", "id")
      project = data.dig("project", "name") || data.dig("project", "id")

      fields = {
        "event" => event,
        "title" => title_for(event, data, project),
        "status" => Alert::STATUS_FIRING,
        "fingerprint" => Digest::SHA256.hexdigest([ event, data.dig("project", "id"), service ].join("\n"))
      }
      fields["service"] = service.to_s if service.present?
      fields["environment"] = data.dig("environment", "id").to_s if data.dig("environment", "id").present?

      [ item(fields, payload) ]
    end

    def self.title_for(event, data, project)
      subject = data.dig("service", "name") || data.dig("job", "name") || data.dig("addon", "name")
      label = event.tr(":", " ").humanize
      [ label, subject, project && "(#{project})" ].compact.join(": ").sub(": (", " (")
    end
  end
end
