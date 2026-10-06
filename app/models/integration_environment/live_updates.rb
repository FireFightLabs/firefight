# Whether what this connection reaches follows its provider's changes between sweeps (Integrations::MapEvents). Each
# row has its own address for the provider's events and the secret they are signed with, which Firefight keeps when it
# registered the webhook itself and an admin pastes when the provider is set up by hand.
module IntegrationEnvironment::LiveUpdates
  extend ActiveSupport::Concern

  # What a person reads about live updates on one connection. on says whether changes reach the map between sweeps,
  # last_event_at when the provider last said something changed, and reason why they do not, or what is wrong with one
  # of two ways in while the other still works, or while they are on, what they do not follow.
  State = Data.define(:on, :last_event_at, :reason)

  # What a person may set up at the provider to send changes as they happen, for a provider that offers it. It holds the
  # sentences saying what it does, the button's words, each place with when it last sent something (nil while it has
  # not) or why it cannot be set up there, why no setup can be made anywhere, if so, and how to remove it.
  Offered = Data.define(:words, :action, :places, :unavailable, :removal)
  OfferedPlace = Data.define(:place, :label, :sent_at, :unavailable)

  # A webhook Firefight registers changes how the connection is set up at the provider, recorded as such.
  MAP_EVENTS_WEBHOOK_ACTION_KEY = Ability::Action.system_key(Ability::Action::RESOURCE_INTEGRATIONS, Ability::Action::ACTION_UPDATE)
  MAP_EVENTS_WEBHOOK_LABEL = "Live updates".freeze
  WEBHOOK_REGISTER = "register".freeze
  WEBHOOK_REFRESH = "refresh".freeze
  WEBHOOK_REMOVE = "remove".freeze
  # A registration the provider refused for its plan or a limit waits this long before Firefight tries on its own again.
  MAP_EVENTS_REFUSED_RETRY = 1.day
  # A change log read due within this is read now, since polls are queued once a minute.
  MAP_EVENTS_POLL_SLACK = 30.seconds

  included do
    encrypts :map_events_secret
    normalizes :map_events_secret, with: ->(value) { value.to_s.strip.presence }
  end

  def map_event_source = Integrations::Provider.for(integration.provider).map_events

  # nil for a provider that cannot say what changed, whose connection is read at each sweep only.
  def live_updates
    source = map_event_source
    return unless source

    on = live_updates_on?(source)
    reason = live_updates_off_reason(source) || (source.limits if on)
    State.new(on: on, last_event_at: map_events_received_at, reason: reason)
  end

  def live_updates_offer
    source = map_event_source
    return unless source&.offers?

    places = source.offers(self).map do |offer|
      OfferedPlace.new(place: offer.place, label: offer.label, sent_at: map_events_sent_at(offer.place), unavailable: offer.unavailable)
    end
    Offered.new(words: source.offer_words, action: source.offer_action, places: places, unavailable: source.offer_unavailable_reason,
                removal: source.removal_words(self, places.select(&:sent_at).map(&:place)))
  end

  # The provider's own page that sets one place up, with the connection's address and secret in it.
  def live_updates_setup_link(place)
    map_event_source.offer_link(self, place: place, url: Integrations::MapEvents.url_for(self), secret: map_events_secret)
  end

  # Why a person cannot set the provider up to send changes from this place, or nil.
  def live_updates_setup_blocked_reason(place)
    source = map_event_source
    return "#{integration.name} cannot be set up to send its changes." unless source&.offers?
    return "#{integration.name} is switched off. Switch it on first." unless integration.operational? && enabled?
    offered = source.offers(self).find { |offer| offer.place == place }
    return "#{integration.name} does not read #{place.presence || 'that place'}." unless offered
    return source.offer_unavailable_reason || offered.unavailable if source.offer_unavailable_reason || offered.unavailable
    return "Firefight's own address is not set, so there is nowhere to send changes." unless Integrations::MapEvents.url_for(self)

    "Firefight has not made this connection's key yet. Try again in a minute." if map_events_secret.blank?
  end

  # How to remove what a person set up at the provider, said when the connection is removed, or nil when nothing sent.
  def live_updates_removal_words
    source = map_event_source
    source.removal_words(self, map_events_sent_from.keys) if source&.offers? && map_events_sent_from.present?
  end

  # Records that a place sent a verified delivery, or that its setup is being removed. One statement, so two deliveries at
  # once each keep their place.
  def map_events_sent!(place, ended: false)
    rows = self.class.where(id: id)
    return rows.update_all([ "map_events_sent_from = map_events_sent_from - ?", place ]) if ended

    rows.update_all([ "map_events_sent_from = map_events_sent_from || jsonb_build_object(?::text, ?::text)", place, Time.current.utc.iso8601 ])
  end

  def map_events_sent_at(place) = map_events_sent_from[place]&.then { |stamp| Time.iso8601(stamp) }

  # Gives the row the secret a provider set up by a person sends with, once.
  def give_map_events_secret!
    return if map_events_secret.present?

    with_lock { update!(map_events_secret: SecureRandom.hex(32)) if map_events_secret.blank? }
  end

  # Whether an admin sends the provider's changes to the connection's address and pastes the signing secret.
  def map_events_set_up_by_hand? = map_event_source.then { |source| source.present? && source.setup_steps.any? && !source.registers? }

  def map_events_secret_set? = map_events_secret.present?

  # The secret an admin pasted from the provider. Saving it again replaces it.
  def save_map_events_secret!(secret)
    update!(map_events_secret: secret, map_events_error: nil)
  end

  # Firefight registers, extends and removes the provider's webhook with the connection's own credentials, and no person
  # asked it to, so each call is in the activity log under the map sweep, as its reads are. change says which (register,
  # refresh or remove). Returns the block's result, and a call that fails is recorded with the provider's words.
  def record_map_events_webhook!(change)
    invocation = AbilityGateway.record!(
      decision: Ability::Invocation::DECISION_ALLOW, completed_at: nil, principal: SystemAgent.map_sweep,
      action: Ability::Action.lookup(MAP_EVENTS_WEBHOOK_ACTION_KEY, integration.workspace), action_key: MAP_EVENTS_WEBHOOK_ACTION_KEY,
      workspace: integration.workspace, scope: {},
      params: { "webhook" => change, "connection" => integration.slug, "environment" => environment&.slug }.compact,
      context: { source: AbilityGateway::SOURCE_MAP_SWEEP, triggered_by_label: MAP_EVENTS_WEBHOOK_LABEL }
    )
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = yield
    invocation.finalize!(outcome: Ability::Invocation::OUTCOME_SUCCESS, duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round)
    result
  rescue StandardError => error
    invocation&.finalize!(outcome: Ability::Invocation::OUTCOME_ERROR, error_summary: Ability::Invocation.summary_of(error.message))
    raise
  end

  # Whether Firefight registers the provider's webhook now on its own. Not while one is registered, a person turned live
  # updates off, or a person is to decide what it costs. A registration the provider refused for its plan or a limit is
  # tried again a day later, so the activity log holds one try a day. now is a connection change, which tries at once.
  def map_events_registration_due?(now: false)
    return false if map_events_webhook_id.present? || map_events_turned_off_at.present?
    return now if map_events_confirmation.present?

    now || map_events_refused_at.nil? || map_events_refused_at <= MAP_EVENTS_REFUSED_RETRY.ago
  end

  # Why a person cannot turn live updates on for this connection, or nil.
  def live_updates_turn_on_blocked_reason
    source = map_event_source
    return "#{integration.name} cannot register for its changes." unless source&.registers?
    return "#{integration.name} is switched off. Switch it on first." unless integration.operational? && enabled?

    "Live updates are already on for #{integration.name}." if map_events_webhook_id.present?
  end

  # Why a person cannot turn live updates off, or nil. Only a connection a person decided on can be turned off, since
  # anywhere else Firefight's webhook costs the account nothing.
  def live_updates_turn_off_blocked_reason
    return "Live updates are already off for #{integration.name}." if map_events_webhook_id.blank?

    "Firefight's webhook costs #{integration.name} nothing, so live updates stay on while it is connected." if map_events_confirmation.blank?
  end

  # What turning live updates on does, for the person about to, said before they confirm.
  def live_updates_turn_on_words
    map_events_confirmation.presence || "Firefight adds a webhook to #{integration.name}, so its changes reach the map within about a minute."
  end

  def live_updates_turn_off_words
    "Firefight removes its webhook from #{integration.name}, which frees it for one of your own. The map then updates at each hourly sweep."
  end

  # Whether the provider's change log is read now. Each is read as often as its source says, and one the provider refused
  # for what the connection may read waits a day.
  def map_events_poll_due?(at: Time.current)
    source = map_event_source
    return false unless source&.polls?
    return false if map_events_refused_at && map_events_refused_at > at - MAP_EVENTS_REFUSED_RETRY

    map_events_polled_at.nil? || map_events_polled_at <= at - source.poll_every + MAP_EVENTS_POLL_SLACK
  end

  # Gives the row its address once. The update names the empty token, so two sweeps at once give it one.
  def give_map_events_token!
    return if map_events_token.present?

    self.class.where(id: id, map_events_token: nil).update_all(map_events_token: SecureRandom.urlsafe_base64(24), updated_at: Time.current)
    reload
  end

  private

  def live_updates_on?(source)
    return false unless integration.operational? && enabled?
    return true if source.polls? && map_events_error.blank?
    return map_events_sent_from.present? if source.offers?
    return installation_id.present? && Integrations::MapEvents.app_secret(integration.provider).present? if source.app_wide?
    return map_events_webhook_id.present? && !map_events_lapsed? if source.registers?

    map_events_secret_set?
  end

  def live_updates_off_reason(source)
    name = integration.name
    return "#{name} is switched off, so changes there do not reach the map." unless integration.operational? && enabled?
    return "Live updates were turned off, so the map updates at each sweep." if source.registers? && map_events_turned_off_at.present?
    if map_events_error.present?
      if source.offers? && map_events_sent_from.present?
        return Integrations::Sentence.join("Firefight could not read #{name}'s change log", map_events_error,
                                           after: "Changes still arrive as they happen from #{map_events_sent_from.keys.to_sentence}.")
      end
      after = map_events_refused_at ? "Firefight tries again tomorrow. The map still updates at each sweep." : "The map still updates at each sweep."
      return Integrations::Sentence.join("Firefight could not follow #{name}'s changes", map_events_error, after: after)
    end
    if source.registers? && map_events_webhook_id.blank? && map_events_confirmation.present?
      return "Firefight asks before adding its webhook to #{name}. #{map_events_confirmation}"
    end
    return if source.polls?

    if source.app_wide?
      app = "Firefight's #{ResourceMap.provider_name(integration.provider)} app"
      return "#{app} is not set up to send changes, so the map updates at each sweep." if Integrations::MapEvents.app_secret(integration.provider).blank?

      return installation_id.present? ? nil : "#{name} was not connected through #{app}, so its changes reach the map at each sweep."
    end
    return "#{name}'s registration for changes lapsed. Firefight registers again at the next sweep." if source.registers? && map_events_lapsed?
    return "Firefight registers for #{name}'s changes at the next sweep." if source.registers? && map_events_webhook_id.blank?

    "Send #{name}'s changes to Firefight and save the signing secret under Integrations to turn them on." if !source.registers? && !map_events_secret_set?
  end

  def map_events_lapsed? = map_events_expires_at.present? && map_events_expires_at <= Time.current
end
