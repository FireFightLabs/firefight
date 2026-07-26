class IntegrationSerializer < BaseSerializer
  object_as :integration

  type :string
  def id
    integration.id
  end

  attributes(
    provider: { type: :string },
    name: { type: :string },
    slug: { type: :string }
  )

  type :boolean
  def disabled
    integration.disabled_at.present?
  end

  type "{ id: string; environmentId: string | null; environmentName: string | null; enabled: boolean; healthStatus: string; healthError: string | null }[]"
  def environments
    integration.integration_environments.map do |row|
      { id: row.id, environmentId: row.catalog_entry_id, environmentName: row.environment&.name,
        enabled: row.enabled, healthStatus: row.health_status, healthError: row.health_error }
    end
  end

  type "{ id: string; name: string; description: string | null; actionKey: string; readOnly: boolean; enabled: boolean }[]"
  def tools
    integration.tools.order(:name).map do |tool|
      { id: tool.id, name: tool.name, description: tool.description,
        actionKey: tool.action_key, readOnly: tool.read_only, enabled: tool.enabled }
    end
  end
end
