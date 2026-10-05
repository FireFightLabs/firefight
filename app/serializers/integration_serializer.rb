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
  # choices are the fields chosen after connecting, each with what the connection learned to choose from and the value
  # chosen, or null.
  type "{ id: string; environmentId: string | null; environmentName: string | null; enabled: boolean; healthStatus: #{HEALTH_UNION}; healthError: string | null; settings: { label: string; value: string }[]; choices: { key: string; label: string; hint: string; value: string | null; options: { value: string; label: string }[] }[] }[]"
  def environments
    integration.integration_environments.map do |row|
      { id: row.id, environmentId: row.catalog_entry_id, environmentName: row.environment&.name,
        enabled: row.enabled, healthStatus: row.health_status, healthError: row.health_error, settings: settings_of(row),
        choices: choices_of(row) }
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
    values = row.fields.merge(integration.address_fields)
    fields = entry.connect_fields.reject(&:learned).filter_map { |field| { label: field.label, value: field.shown(values[field.key]) } if values[field.key].present? }
    [ region, *fields ].compact
  end

  # Only a real choice is offered, two or more learned options. With one there is nothing to choose.
  def choices_of(row)
    entry = IntegrationProvider.find(integration.provider)
    return [] unless entry

    entry.learned_fields.filter_map do |field|
      options = field.options_from(row.learned)
      next if options.size < 2

      { key: field.key, label: field.label, hint: field.hint, value: row.fields[field.key].presence, options: options.map(&:to_h) }
    end
  end
end
