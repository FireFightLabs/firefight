class AlertSourceSettingsSerializer < BaseSerializer
  object_as :alert_source

  type :string
  def id
    alert_source.id
  end

  attributes(
    name: { type: :string },
    provider: { type: :string },
    enabled: { type: :boolean },
    secret_token: { type: :string }
  )

  type :string
  def ingest_path
    "/api/v1/alerts/#{alert_source.endpoint_path}"
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
