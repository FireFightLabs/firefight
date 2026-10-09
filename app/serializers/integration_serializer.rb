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

  # settings are what the connection was set up with beside its credentials, each with its label. choices are the
  # fields chosen after connecting, with what the connection learned to choose from.
  # liveUpdates is null for a provider that cannot say what changed. setup is for a provider an admin sends changes from
  # by hand, and its address is null while Firefight's own address is not set. turnOn and turnOff are what a person
  # confirms before switching live updates, and turnOnBlocked and turnOffBlocked say why they cannot. offer is for a
  # provider a person sets up from a template. Its link is a redirect (live_updates_setup), so the connection's secret
  # is never in the page.
  OFFER_TYPE = "{ words: string; action: string; unavailable: string | null; removal: string; places: { place: string; label: string; sentAt: string | null; unavailable: string | null }[] } | null".freeze
  LIVE_UPDATES_TYPE = "{ on: boolean; lastEventAt: string | null; reason: string | null; setup: { address: string | null; steps: string[]; secretSet: boolean; manySecrets: boolean; secretCount: number; forgetSecrets: string | null; forgetSecretsBlockedReason: string | null } | null; offer: #{OFFER_TYPE}; turnOn: string | null; turnOff: string | null; turnOnBlocked: string | null; turnOffBlocked: string | null } | null".freeze

  # scopes is what the connection reads at its provider for a provider that names it by a scope field, such as a host's
  # projects. It holds the field, the values chosen (one value, the field's all, for every one the credentials can
  # read) and the names they were last listed with. null for any other provider.
  SCOPES_TYPE = "{ key: string; label: string; hint: string; values: string[]; options: { value: string; label: string }[] } | null".freeze

  # installation is there for a connection made through an app installed at the provider: what the provider calls the
  # app, the account it is on, the address of its settings there, and while the provider says it was removed, suspended
  # or given nothing, the state with its label and why the connection stopped. null otherwise.
  INSTALLATION_STATE_UNION = Integrations::Installations::STATES.map(&:inspect).join(" | ")
  INSTALLATION_TYPE = "{ app: string; account: string | null; page: string | null; state: #{INSTALLATION_STATE_UNION} | null; label: string | null; reason: string | null } | null".freeze

  type "{ id: string; environmentId: string | null; environmentName: string | null; enabled: boolean; healthStatus: #{HEALTH_UNION}; healthError: string | null; settings: { label: string; value: string }[]; choices: { key: string; label: string; hint: string; value: string | null; options: { value: string; label: string }[] }[]; scopes: #{SCOPES_TYPE}; liveUpdates: #{LIVE_UPDATES_TYPE}; installation: #{INSTALLATION_TYPE} }[]"
  def environments
    integration.integration_environments.map do |row|
      { id: row.id, environmentId: row.catalog_entry_id, environmentName: row.environment&.name,
        enabled: row.enabled, healthStatus: row.health_status, healthError: row.health_error, settings: settings_of(row),
        choices: choices_of(row), scopes: scopes_of(row), liveUpdates: live_updates_of(row), installation: installation_of(row) }
    end
  end

  # accessMissing says what the app installation was not granted that the tool needs, or null.
  type "{ id: string; name: string; description: string | null; actionKey: string; readOnly: boolean; enabled: boolean; available: boolean; toggleBlockedReason: string | null; accessMissing: string | null }[]"
  def tools
    integration.tools.sort_by(&:name).map do |tool|
      { id: tool.id, name: tool.name, description: tool.description,
        actionKey: tool.action_key, readOnly: tool.read_only, enabled: tool.enabled,
        available: tool.available?, toggleBlockedReason: tool.toggle_blocked_reason, accessMissing: tool.access_missing_reason }
    end
  end

  # The paths Halon may not change in the connection's repositories, as an admin listed them. null for a provider that
  # holds no code.
  type "string[] | null"
  def protected_paths
    integration.protected_paths if integration.holds_code?
  end

  # The app installations disconnecting may also remove from their account at the provider, one for each the connection
  # was made through, with what the choice reads and why it cannot be made (another connection still uses it), or null.
  type "{ installationId: string; label: string; page: string | null; blockedReason: string | null }[]"
  def installations
    integration.integration_environments.select { |row| Integrations::Installations.installed?(row) && row.installation_state != Integrations::Installations::REMOVED }
               .uniq(&:installation_id).map do |row|
      provider = Integrations::Installations.provider_name(row)
      { installationId: row.installation_id, label: "Also remove the Firefight app from #{row.installation_account || 'this account'} on #{provider}",
        page: row.installation_page, blockedReason: row.uninstall_blocked_reason }
    end
  end

  private

  def settings_of(row)
    entry = IntegrationProvider.find(integration.provider)
    return [] unless entry

    region = ({ label: "Region", value: integration.region.label } if entry.regional? && integration.region)
    values = row.fields.merge(integration.address_fields)
    shown = integration.native? ? entry.connect_fields.reject { |field| field.learned || field.scope } : entry.connect_fields.reject(&:learned)
    fields = shown.filter_map { |field| { label: field.label, value: field.shown(values[field.key]) } if values[field.key].present? }
    [ region, *fields ].compact
  end

  def installation_of(row)
    return unless Integrations::Installations.installed?(row)

    { app: Integrations::Installations.app_name(row), account: row.installation_account, page: row.installation_page, state: row.installation_state,
      label: Integrations::Installations.state_label(row), reason: Integrations::Installations.stopped_reason(row) }
  end

  def live_updates_of(row)
    state = row.live_updates
    return unless state

    if row.map_events_set_up_by_hand?
      setup = { address: Integrations::MapEvents.url_for(row), steps: row.map_event_source.setup_steps, secretSet: row.map_events_secret_set?,
                manySecrets: row.map_event_source.many_secrets?, secretCount: row.map_events_secrets.size,
                forgetSecrets: (row.forget_map_events_secrets_words unless row.forget_map_events_secrets_blocked_reason),
                forgetSecretsBlockedReason: row.forget_map_events_secrets_blocked_reason }
    end
    offer = row.live_updates_offer&.then do |offered|
      { words: offered.words, action: offered.action, unavailable: offered.unavailable, removal: offered.removal,
        places: offered.places.map { |place| { place: place.place, label: place.label, sentAt: place.sent_at&.utc&.iso8601, unavailable: place.unavailable } } }
    end
    { on: state.on, lastEventAt: state.last_event_at&.utc&.iso8601, reason: state.reason, setup: setup, offer: offer,
      turnOn: (row.live_updates_turn_on_words unless row.live_updates_turn_on_blocked_reason),
      turnOff: (row.live_updates_turn_off_words unless row.live_updates_turn_off_blocked_reason),
      turnOnBlocked: row.live_updates_turn_on_blocked_reason, turnOffBlocked: row.live_updates_turn_off_blocked_reason }
  end

  def scopes_of(row)
    settings = Integrations::ConnectionSettings.of(row)
    field = settings.scope_field
    return unless field && integration.native?

    named = settings.chosen_scopes.map { |id| { value: id, label: settings.scope_name(id) } }
    learned = settings.known_scopes.map { |id| { value: id, label: settings.scope_name(id) } }
    { key: field.key, label: field.label, hint: field.hint, values: settings.chosen_scopes, options: (named + learned).uniq { |option| option[:value] } }
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
