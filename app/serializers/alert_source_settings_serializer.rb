class AlertSourceSettingsSerializer < BaseSerializer
  object_as :alert_source

  # Stands in for the secret in an address that carries one. The whole address is fetched on demand by someone who can
  # change the source.
  SECRET_MASK = "••••••••".freeze

  type :string
  def id
    alert_source.id
  end

  attributes(
    name: { type: :string },
    provider: { type: :string },
    enabled: { type: :boolean }
  )

  type :string, optional: true
  def last_received_at
    alert_source.last_received_at&.utc&.iso8601
  end

  type :string, optional: true
  def last_rejected_at
    alert_source.last_rejected_at&.utc&.iso8601
  end

  type :string, optional: true
  def last_rejection_reason
    alert_source.last_rejection_reason
  end

  type :string, optional: true
  def secret_summary
    alert_source.secret_summary
  end

  type :string
  def ingest_path
    path = Rails.application.routes.url_helpers.api_v1_alert_ingest_path(endpoint_path: alert_source.endpoint_path)
    AlertProviders.for(alert_source.provider)::SECRET_IN_ADDRESS ? "#{path}/#{SECRET_MASK}" : path
  end

  type "Record<string, string>"
  def severity_map
    alert_source.config.fetch("severity_map", {})
  end

  type "Record<string, string>"
  def field_map
    alert_source.config.fetch("field_map", {})
  end

  type :string, optional: true
  def items_path
    alert_source.config["items_path"]
  end

  type "string[]"
  def fingerprint_fields
    alert_source.fingerprint_fields
  end

  type :number
  def flap_window_minutes
    alert_source.config.fetch("flap_window_minutes", AlertSource::DEFAULT_FLAP_WINDOW_MINUTES).to_i
  end

  type :string
  def created_at
    alert_source.created_at.utc.iso8601
  end
end
