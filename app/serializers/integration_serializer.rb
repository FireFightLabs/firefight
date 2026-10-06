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
  # liveUpdates says whether the provider's changes reach the map between sweeps, null for a provider that cannot say
  # what changed. setup is there for a provider an admin sends them from by hand: the connection's own address (null
  # while Firefight's own address is not set), the steps, and whether a signing secret is saved. turnOn and turnOff are
  # what a person confirms before turning live updates on or off, null where they cannot.
  LIVE_UPDATES_TYPE = "{ on: boolean; lastEventAt: string | null; reason: string | null; setup: { address: string | null; steps: string[]; secretSet: boolean; manySecrets: boolean; secretCount: number; forgetSecrets: string | null; forgetSecretsBlocked: string | null } | null; turnOn: string | null; turnOff: string | null } | null".freeze

  type "{ id: string; environmentId: string | null; environmentName: string | null; enabled: boolean; healthStatus: #{HEALTH_UNION}; healthError: string | null; settings: { label: string; value: string }[]; choices: { key: string; label: string; hint: string; value: string | null; options: { value: string; label: string }[] }[]; liveUpdates: #{LIVE_UPDATES_TYPE} }[]"
  def environments
    integration.integration_environments.map do |row|
      { id: row.id, environmentId: row.catalog_entry_id, environmentName: row.environment&.name,
        enabled: row.enabled, healthStatus: row.health_status, healthError: row.health_error, settings: settings_of(row),
        choices: choices_of(row), liveUpdates: live_updates_of(row) }
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

  def live_updates_of(row)
    state = row.live_updates
    return unless state

    if row.map_events_set_up_by_hand?
      setup = { address: Integrations::MapEvents.url_for(row), steps: row.map_event_source.setup_steps, secretSet: row.map_events_secret_set?,
                manySecrets: row.map_event_source.many_secrets?, secretCount: row.map_events_secrets.size,
                forgetSecrets: (row.forget_map_events_secrets_words unless row.forget_map_events_secrets_blocked_reason),
                forgetSecretsBlocked: row.forget_map_events_secrets_blocked_reason }
    end
    { on: state.on, lastEventAt: state.last_event_at&.utc&.iso8601, reason: state.reason, setup: setup,
      turnOn: (row.live_updates_turn_on_words unless row.live_updates_turn_on_blocked_reason),
      turnOff: (row.live_updates_turn_off_words unless row.live_updates_turn_off_blocked_reason) }
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
