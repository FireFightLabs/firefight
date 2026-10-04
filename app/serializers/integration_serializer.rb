class IntegrationSerializer < BaseSerializer
  object_as :integration

  KIND_UNION = Integration::KINDS.map(&:inspect).join(" | ")
  HEALTH_UNION = IntegrationEnvironment::HEALTH_STATUSES.map(&:inspect).join(" | ")

  type :string
  def id
    integration.id
  end

  attributes(
    provider: { type: :string },
    name: { type: :string },
    slug: { type: :string }
  )

  type KIND_UNION
  def kind
    integration.kind
  end

  type :boolean
  def disabled
    integration.disabled_at.present?
  end

  # settings are what the connection was set up with beside its credentials: the region it is in, when its provider
  # offers more than one, and what the connect form asked, each with its label.
  type "{ id: string; environmentId: string | null; environmentName: string | null; enabled: boolean; healthStatus: #{HEALTH_UNION}; healthError: string | null; settings: { label: string; value: string }[] }[]"
  def environments
    integration.integration_environments.map do |row|
      { id: row.id, environmentId: row.catalog_entry_id, environmentName: row.environment&.name,
        enabled: row.enabled, healthStatus: row.health_status, healthError: row.health_error, settings: settings_of(row) }
    end
  end

  type "{ id: string; name: string; description: string | null; actionKey: string; readOnly: boolean; enabled: boolean; available: boolean; toggleBlockedReason: string | null }[]"
  def tools
    integration.tools.order(:name).map do |tool|
      { id: tool.id, name: tool.name, description: tool.description,
        actionKey: tool.action_key, readOnly: tool.read_only, enabled: tool.enabled,
        available: tool.available?, toggleBlockedReason: tool.toggle_blocked_reason }
    end
  end

  private

  def settings_of(row)
    entry = IntegrationProvider.find(integration.provider)
    return [] unless entry

    region = ({ label: "Region", value: integration.region.label } if entry.regional? && integration.region)
    values = row.fields.merge(integration.path_fields)
    fields = entry.connect_fields.filter_map { |field| { label: field.label, value: values[field.key].to_s } if values[field.key].present? }
    [ region, *fields ].compact
  end
end
