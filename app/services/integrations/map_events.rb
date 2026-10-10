module Integrations
  # Live updates for the resource map. A provider that can say something changed (its definition's map_events, a
  # MapEventSource) sends an event to an address that belongs to one connection, or Firefight reads its change log every
  # few minutes. An event is never taken as the truth. It is a nudge to read the scope it names again, within about a
  # minute, and write what that read found (ResourceMap.apply!). So a duplicate or an event out of order is harmless, and
  # nothing is removed unless the re-read finds the provider no longer has it. The hourly sweep stays as the safety net.
  module MapEvents
    # Events about one scope wait this long, so a burst of them is read again once.
    COALESCE = 30.seconds
    # A webhook that lapses is extended once it has this long left.
    REFRESH_WITHIN = 7.days
    # What Firefight says in a connection's gaps when the provider asked it to slow down while reading a change.
    SLOWED = "%<name>s asked Firefight to slow down, so a change it reported is read at the next sweep.".freeze
    SLOWED_REGISTERING = "%<name>s asked it to slow down, so Firefight registers again at the next sweep.".freeze

    module_function

    def source_of(provider_key) = Provider.for(provider_key).map_events

    # The connection's own address, or nil while Firefight's own address is not set or the row has none yet.
    def url_for(environment_row)
      options = AppUrl.options
      return unless options && environment_row.map_events_token

      Rails.application.routes.url_helpers.api_v1_map_events_url(environment_row.map_events_token, **options)
    end

    # The secret every delivery to a provider's app wide address is signed with, set by whoever runs Firefight.
    def app_secret(provider_key) = ENV["INTEGRATION_#{provider_key.to_s.upcase}_WEBHOOK_SECRET"].presence

    # The connections an app wide delivery is about, by the installation the provider's source reads from it.
    def rows_for_installation(provider_key, installation)
      return IntegrationEnvironment.none if installation.blank?

      IntegrationEnvironment.reachable.where(integrations: { provider: provider_key.to_s })
                            .where("integration_environments.base_config ->> :key = :installation", key: IntegrationEnvironment::INSTALLATION_KEY,
                                                                                                    installation: installation.to_s)
    end

    # Keeps each event once per connection and queues a re-read of each scope a new one names. Answers how many were new.
    def receive!(environment_row, events, received_at: Time.current)
      environment_row.update_columns(map_events_received_at: received_at) if events.any?
      return 0 if events.empty?

      rows = events.map do |event|
        { workspace_id: environment_row.integration.workspace_id, integration_environment_id: environment_row.id,
          provider_event_id: event.provider_id, action: event.action, scope: event.scope.to_job, scope_key: event.scope.key,
          happened_at: event.at, received_at: received_at, created_at: received_at, updated_at: received_at }
      end
      kept = ResourceMap::ReceivedEvent.insert_all(rows, unique_by: :index_resource_map_events_once, returning: %w[scope_key])
      kept.rows.flatten.uniq.each { |scope_key| MapEventJob.set(wait: COALESCE).perform_later(environment_row, scope_key) }
      # A watch reading through this connection checks now rather than at its next minute.
      Conversation::Watches.wake!(environment_row) if kept.rows.any?
      kept.rows.size
    end

    # What a delivery says about pull requests reaches the ones Halon follows through each of these connections at once.
    def nudge_pull_requests!(rows, payload, headers:)
      return if rows.empty?

      nudges = PullRequests.nudges(rows.first.integration.provider, payload, headers: headers)
      rows.each { |row| PullRequestFollowing.nudged!(row, nudges) } if nudges.any?
    end

    # What a delivery says leaked reaches the security module of each workspace these connections belong to, once each.
    def report_security_events!(rows, payload, headers:)
      return if rows.empty?

      events = SecurityEvents.of(rows.first.integration.provider, payload, headers: headers)
      return if events.empty?

      rows.map { |row| row.integration.workspace_id }.uniq.each do |workspace_id|
        events.each { |event| SecurityEventJob.perform_later(workspace_id, event.to_h.stringify_keys) }
      end
    end

    # Reads again what the events waiting on one scope name, and writes it onto the map. A scope the provider cannot read
    # on its own, or a change to what the connection reaches, sweeps the connection in full instead.
    def reread!(environment_row, scope_key)
      events = ResourceMap::ReceivedEvent.claim!(environment_row, scope_key)
      return if events.empty?

      scope = events.first.scope_read
      read_at = Time.current
      partial = environment_row.integration.executor.map_refresh(environment_row, scope) unless scope.everything? || events.any? { |event| event.action == ResourceMap::Event::RESCOPE }
      return swept!(environment_row, events) unless partial

      partial = Provider.for(environment_row.integration.provider).in_firefight_words(partial)
      changed = ResourceMap.apply!(environment_row, partial, scope: scope, at: events.map(&:happened_at).max, read_at: read_at)
      # A code host's re-read of one repository holds its infrastructure files, and takes away only that repository's
      # suggestions when it read it in full.
      ResourceMap::CodeDefinitions.new(environment_row.integration.workspace).record!(environment_row, partial.code_files, read_in_full: partial.code_read)
      MapSweep.written!(environment_row, changed) if changed.any?
      ResourceMap::ReceivedEvent.finish!(events, ResourceMap::ReceivedEvent::OUTCOME_APPLIED)
    rescue RateLimited
      slowed!(environment_row)
      ResourceMap::ReceivedEvent.finish!(events, ResourceMap::ReceivedEvent::OUTCOME_DEFERRED)
    rescue Integrations::Error => error
      Rails.logger.warn({ event: "map_events.reread_failed", integration_environment_id: environment_row.id, error: error.message.truncate(200) }.to_json)
      ResourceMap::ReceivedEvent.finish!(events, ResourceMap::ReceivedEvent::OUTCOME_FAILED)
    end

    # One full sweep for however many events asked for one, since a sweep asked before the last one ran has nothing left.
    def swept!(environment_row, events)
      MapEventSweepJob.set(wait: COALESCE).perform_later(environment_row, Time.current.iso8601(6))
      ResourceMap::ReceivedEvent.finish!(events, ResourceMap::ReceivedEvent::OUTCOME_SWEPT)
    end

    def slowed!(environment_row)
      gap = format(SLOWED, name: environment_row.integration.name)
      environment_row.update!(map_gaps: (environment_row.map_gaps + [ gap ]).uniq)
    end

    # Reads the provider's change log after where it was last read, keeping the new cursor only once its events are kept.
    # A read the provider refused for what the connection may read waits a day (IntegrationEnvironment#map_events_poll_due?).
    def poll!(environment_row)
      source = source_of(environment_row.integration.provider)
      return unless source&.polls?

      environment_row.update_columns(map_events_polled_at: Time.current)
      polled = source.poll(environment_row, since: environment_row.map_events_cursor)
      receive!(environment_row, polled.events)
      environment_row.update!(map_events_cursor: polled.cursor, map_events_error: nil, map_events_refused_at: nil)
      # One scope's change log that could not be read leaves live updates on for the rest, and is said with the map's gaps.
      environment_row.update!(map_gaps: (environment_row.map_gaps + [ polled.error ]).uniq) if polled.error
    rescue RateLimited
      nil
    rescue MapEventSource::Refused => error
      environment_row.update!(map_events_error: error.message, map_events_refused_at: Time.current)
    rescue Integrations::Error => error
      environment_row.update!(map_events_error: error.message)
    end

    # Gives a connection whose provider sends changes its own address, and registers the provider's webhook when
    # Firefight can. Run on connecting and with each hourly sweep, so a registration that failed is tried again, one the
    # provider refused for its plan or a limit a day later (IntegrationEnvironment#map_events_registration_due?). now is a
    # connection change, which tries at once and asks again whether a person should decide first, and reads a change log
    # at the next minute's poll, one the provider refused included.
    def prepare!(environment_row, now: false)
      source = source_of(environment_row.integration.provider)
      return unless source

      environment_row.give_map_events_token!
      environment_row.give_map_events_secret! if source.offers?
      environment_row.update_columns(map_events_refused_at: nil, map_events_polled_at: nil) if now && source.polls? && !source.registers?
      return unless source.registers?

      register!(environment_row, source) if environment_row.map_events_registration_due?(now: now) || register_again?(environment_row, source)
    end

    # Whether a registration from before has fallen short of what the connection reaches. A provider that cannot be asked
    # now is asked again at the next sweep.
    def register_again?(environment_row, source)
      return false unless environment_row.map_events_webhook_id.present? && environment_row.map_events_turned_off_at.nil?
      return true if scopes_changed?(environment_row)
      return false unless source.respond_to?(:register_again?)

      url = url_for(environment_row)
      url.present? && source.register_again?(environment_row, url: url)
    rescue Integrations::Error => error
      Rails.logger.warn({ event: "map_events.register_again_unknown", integration_environment_id: environment_row.id, error: error.message.truncate(200) }.to_json)
      false
    end

    # Whether the connection reaches other scopes than its registration covers, such as a project chosen, dropped or
    # added since (Integrations::Scopes), so registering again follows the new ones and stops following the old.
    def scopes_changed?(environment_row)
      covered = environment_row.map_events_scopes
      settings = ConnectionSettings.of(environment_row)
      covered.present? && settings.scope_field.present? && covered.sort != settings.scopes.sort
    end

    # Notes where a verified delivery came from, for a provider a person set up to send changes, so the connection says
    # which of its places send them, and forgets a place whose setup says it is being removed.
    def delivered!(environment_row, source, payload)
      return unless source.offers?

      place = source.delivery_place(payload)
      environment_row.map_events_sent!(place, ended: source.delivery_ends?(payload)) if place
    end

    # A person turned live updates on, having read what it costs when the source asked first. Tried at once.
    def turn_on!(environment_row)
      source = source_of(environment_row.integration.provider)
      environment_row.update!(map_events_turned_off_at: nil)
      environment_row.give_map_events_token!
      register!(environment_row, source, decided: true)
    end

    # A person turned live updates off, which takes Firefight's webhook back. Firefight does not register again on its
    # own until someone turns them on. Raises when the provider could not be reached, leaving them on.
    def turn_off!(environment_row)
      source = source_of(environment_row.integration.provider)
      remove!(environment_row, source) if environment_row.map_events_webhook_id.present?
      environment_row.update!(map_events_turned_off_at: Time.current, map_events_error: nil, map_events_refused_at: nil)
    end

    # Registers the webhook, unless the source says what it would cost the account and nobody decided yet, in which case
    # the connection waits for a person (map_events_confirmation). What it cost stays with the row, so the person who
    # turned it on can turn it off.
    def register!(environment_row, source, decided: false)
      url = url_for(environment_row)
      return environment_row.update!(map_events_error: "Firefight's own address is not set, so there is nowhere to send changes.") unless url

      asked = source.asks_first? ? source.confirmation_for(environment_row, url: url) : nil
      return environment_row.update!(map_events_confirmation: asked, map_events_error: nil, map_events_refused_at: nil) if asked && !decided

      webhook = environment_row.record_map_events_webhook!(IntegrationEnvironment::WEBHOOK_REGISTER) { source.register(environment_row, url: url) }
      environment_row.update!(map_events_webhook_id: webhook.id, map_events_secret: webhook.secret, map_events_expires_at: webhook.expires_at,
                              map_events_scopes: webhook.scopes, map_events_confirmation: asked,
                              map_events_error: nil, map_events_refused_at: nil)
    rescue RateLimited
      environment_row.update!(map_events_error: format(SLOWED_REGISTERING, name: environment_row.integration.name))
    rescue MapEventSource::Refused => error
      environment_row.update!(map_events_error: error.message, map_events_refused_at: Time.current)
    rescue Integrations::Error => error
      environment_row.update!(map_events_error: error.message)
    end

    def remove!(environment_row, source)
      environment_row.record_map_events_webhook!(IntegrationEnvironment::WEBHOOK_REMOVE) { source.remove(environment_row, environment_row.map_events_webhook_id) }
      environment_row.update!(map_events_webhook_id: nil, map_events_expires_at: nil, map_events_scopes: nil)
    end

    # Extends a registered webhook before it lapses.
    def refresh!(environment_row)
      source = source_of(environment_row.integration.provider)
      return unless source.respond_to?(:refresh) && environment_row.map_events_webhook_id.present?

      expires_at = environment_row.record_map_events_webhook!(IntegrationEnvironment::WEBHOOK_REFRESH) { source.refresh(environment_row, environment_row.map_events_webhook_id) }
      environment_row.update!(map_events_expires_at: expires_at, map_events_error: nil)
    rescue Integrations::Error => error
      environment_row.update!(map_events_error: error.message)
    end

    # Takes back what Firefight registered, while the connection's credentials still reach the provider. What a person set
    # up to send changes stays at the provider, so its secret is forgotten and nothing it sends is accepted again.
    def connection_removed(integration)
      source = source_of(integration.provider)
      integration.integration_environments.update_all(map_events_secret: nil, map_events_sent_from: {}, updated_at: Time.current) if source&.offers?
      return unless source&.respond_to?(:remove)

      integration.integration_environments.where.not(map_events_webhook_id: nil).find_each do |row|
        remove!(row, source)
      rescue Integrations::Error => error
        Rails.logger.warn({ event: "map_events.webhook_remove_failed", integration_environment_id: row.id, error: error.message.truncate(200) }.to_json)
      end
    end
  end
end
