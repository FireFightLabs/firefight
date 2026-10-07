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
  # what a person confirms before turning live updates on or off, null where they cannot. offer is there for a provider
  # a person may set up to send changes as they happen from a template, with what it does, the button's words, each place
  # with when it last sent something or why it cannot be set up there, why it cannot be set up at all (or null) and how
  # to remove it. The link itself is a
  # redirect (live_updates_setup), so the connection's secret is never in the page.
  OFFER_TYPE = "{ words: string; action: string; unavailable: string | null; removal: string; places: { place: string; label: string; sentAt: string | null; unavailable: string | null }[] } | null".freeze
  LIVE_UPDATES_TYPE = "{ on: boolean; lastEventAt: string | null; reason: string | null; setup: { address: string | null; steps: string[]; secretSet: boolean; manySecrets: boolean; secretCount: number; forgetSecrets: string | null; forgetSecretsBlocked: string | null } | null; offer: #{OFFER_TYPE}; turnOn: string | null; turnOff: string | null } | null".freeze

  # installation is there for a connection made through an app installed at the provider: what the provider calls the
  # app, the account it is on, the
  # address of its settings there, and while the provider says it was removed, suspended or given nothing, the state with
  # its label and why the connection stopped. null otherwise.
  INSTALLATION_STATE_UNION = Integrations::Installations::STATES.map(&:inspect).join(" | ")
  INSTALLATION_TYPE = "{ app: string; account: string | null; page: string | null; state: #{INSTALLATION_STATE_UNION} | null; label: string | null; reason: string | null } | null".freeze

  type "{ id: string; environmentId: string | null; environmentName: string | null; enabled: boolean; healthStatus: #{HEALTH_UNION}; healthError: string | null; settings: { label: string; value: string }[]; choices: { key: string; label: string; hint: string; value: string | null; options: { value: string; label: string }[] }[]; liveUpdates: #{LIVE_UPDATES_TYPE}; installation: #{INSTALLATION_TYPE} }[]"
  def environments
    integration.integration_environments.map do |row|
      { id: row.id, environmentId: row.catalog_entry_id, environmentName: row.environment&.name,
        enabled: row.enabled, healthStatus: row.health_status, healthError: row.health_error, settings: settings_of(row),
        choices: choices_of(row), liveUpdates: live_updates_of(row), installation: installation_of(row) }
    end
  end

  # accessMissing says what the app installation was not granted that the tool needs, or null.
  type "{ id: string; name: string; description: string | null; actionKey: string; readOnly: boolean; enabled: boolean; available: boolean; toggleBlockedReason: string | null; accessMissing: string | null }[]"
  def tools
    integration.tools.order(:name).map do |tool|
      { id: tool.id, name: tool.name, description: tool.description,
        actionKey: tool.action_key, readOnly: tool.read_only, enabled: tool.enabled,
        available: tool.available?, toggleBlockedReason: tool.toggle_blocked_reason, accessMissing: tool.access_missing_reason }
    end
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
    fields = entry.connect_fields.reject(&:learned).filter_map { |field| { label: field.label, value: field.shown(values[field.key]) } if values[field.key].present? }
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
                forgetSecretsBlocked: row.forget_map_events_secrets_blocked_reason }
    end
    offer = row.live_updates_offer&.then do |offered|
      { words: offered.words, action: offered.action, unavailable: offered.unavailable, removal: offered.removal,
        places: offered.places.map { |place| { place: place.place, label: place.label, sentAt: place.sent_at&.utc&.iso8601, unavailable: place.unavailable } } }
    end
    { on: state.on, lastEventAt: state.last_event_at&.utc&.iso8601, reason: state.reason, setup: setup, offer: offer,
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
