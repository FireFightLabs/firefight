class AlertSourceSettingsSerializer < BaseSerializer
  object_as :alert_source

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

  type :string
  def ingest_path
    Rails.application.routes.url_helpers.api_v1_alert_ingest_path(endpoint_path: alert_source.endpoint_path)
  end

  type "Record<string, string>"
  def severity_map
    alert_source.config.fetch("severity_map", {})
  end

  type :string
  def created_at
    alert_source.created_at.utc.iso8601
  end
end
