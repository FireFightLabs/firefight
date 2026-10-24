# Whether what this connection reaches follows its provider's changes between sweeps (Integrations::MapEvents). Each
# row has its own address for the provider's events and the secret they are signed with, which Firefight keeps when it
# registered the webhook itself and an admin pastes when the provider is set up by hand.
module IntegrationEnvironment::LiveUpdates
  extend ActiveSupport::Concern

  # What a person reads about live updates on one connection. on says whether changes reach the map between sweeps,
  # last_event_at when the provider last said something changed, and reason why they do not, or what is wrong with one
  # of two ways in while the other still works, or while they are on, what they do not follow. For a provider whose
  # change log is read and that is sent changes as well, checked_every says how often the log is read and second_way
  # how the other way in stands, so a person reads each apart. Both are nil for any other provider.
  State = Data.define(:on, :last_event_at, :reason, :checked_every, :second_way) do
    def initialize(on:, last_event_at:, reason:, checked_every: nil, second_way: nil) = super
  end
  # The second way in: its status line, whether it works, and why it could not be set up, if so.
  SecondWay = Data.define(:line, :on, :reason)

  # What a person may set up at the provider to send changes as they happen, for a provider that offers it. It holds the
  # sentences saying what it does, the button's words, each place with when it last sent something (nil while it has
  # not) or why it cannot be set up there, why no setup can be made anywhere, if so, and how to remove it.
  Offered = Data.define(:words, :action, :places, :unavailable, :removal)
  OfferedPlace = Data.define(:place, :label, :sent_at, :unavailable)
  # The one switch for a provider Firefight registers its webhook with. It reads Turn on while none is registered and
  # Turn off while one is, with what it does, why it cannot be pressed now, if so, and what it switches, live updates or
  # for a provider whose change log is read either way, the second way in, such as instant updates.
  Toggle = Data.define(:turns_on, :words, :blocked_reason, :subject)

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
    second_way = live_updates_second_way(source)
    State.new(on: on, last_event_at: map_events_received_at, reason: reason, second_way: second_way,
              checked_every: ("every #{source.poll_every.inspect}" if second_way))
  end

  # What the provider's changes reach the map at without live updates, the sweep at the interval this connection is
  # swept, such as "hourly sweep".
  def map_sweep_words
    every = integration.executor.map_every(integration)
    { 1.hour => "hourly sweep", 1.day => "daily sweep" }.fetch(every) { "sweep every #{every.inspect}" }
  rescue Integrations::Error
    "hourly sweep"
  end

  # What a person turns on and off with live_updates_toggle, said in its button, its dialog and its toast.
  def live_updates_subject
    source = map_event_source
    source&.polls? && source.deliveries_name ? source.deliveries_name.downcase_first : "live updates"
  end

  # What a verified delivery does once a secret is saved, said in the toast.
  def map_events_saved_words = map_event_source.deliveries_words || "Changes #{integration.name} sends now reach the map."

  # What the secret is for and what a verified delivery does, said under the secret.
  def map_events_secret_note
    source = map_event_source
    accepted = if source.many_secrets?
      "Each webhook signs with a secret of its own, so add each one. Firefight accepts a change signed with any of them, and a secret is never shown again."
    elsif source.makes_secret?
      "Firefight accepts what #{integration.name} sends only when it carries this secret, and the secret is shown once."
    else
      "Firefight accepts a change only when it is signed with this secret, and the secret is never shown again."
    end
    Integrations::Sentence.all(accepted, source.deliveries_words || "A change is never taken as it is sent. Firefight reads what it names again and updates the map.")
  end

  # Whether Firefight makes the signing secret for a provider set up by hand, and shows it once.
  def map_events_secret_made? = map_events_set_up_by_hand? && map_event_source.makes_secret?

  # Makes a new signing secret for a provider that takes whatever secret it is given, and answers it so it is shown once,
  # or nil. One already saved is replaced only when replace says so, so a second admin's stale Make never breaks the
  # webhook the first one set up, and it is made under the row's lock, so two at once make one.
  def make_map_events_secret!(replace: false)
    with_lock do
      next nil if map_events_secret_set? && !replace

      SecureRandom.hex(32).tap { |secret| update!(map_events_secret: secret) }
    end
  end

  def map_events_secret_already_made_words = "A signing secret is already saved for #{integration.name}. Replace it to get a new one."

  # What replacing a secret Firefight made does, said before a person confirms. nil while none is saved.
  def replace_map_events_secret_words
    return unless map_events_secret_set?

    "The secret saved now stops working at once, so what #{integration.name} sends is refused until each of its webhooks has " \
      "the new one. The new secret is shown once."
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
  def map_events_set_up_by_hand? = map_event_source.then { |source| source.present? && source.setup_steps.any? && !source.registers_for?(self) }

  def map_events_secret_set? = map_events_secret.present?

  # Every secret a delivery may be signed with. A provider whose webhooks each sign with their own (many_secrets?) keeps
  # one a line, which no secret holds.
  def map_events_secrets = map_events_secret.to_s.split("\n").compact_blank

  # The secret an admin pasted from the provider. Saving it again replaces it, or joins the others when each of the
  # provider's webhooks has its own.
  def save_map_events_secret!(secret)
    secret = secret.to_s.strip
    secret = (map_events_secrets + [ secret ]).uniq.join("\n") if map_event_source&.many_secrets?
    update!(map_events_secret: secret, map_events_error: nil)
  end

  # Drops every saved secret, so nothing the provider sends counts until an admin saves one again.
  def forget_map_events_secrets!
    update!(map_events_secret: nil)
  end

  # Why a person cannot forget the saved secrets, or nil. Only a provider whose webhooks each sign with their own keeps
  # several, and anywhere else saving a new secret replaces the one there is.
  def forget_map_events_secrets_blocked_reason
    return "#{integration.name} keeps one signing secret, which saving a new one replaces." unless map_events_set_up_by_hand? && map_event_source.many_secrets?

    "No signing secret is saved for #{integration.name}." unless map_events_secret_set?
  end

  def forget_map_events_secrets_words
    count = map_events_secrets.size
    "Firefight forgets the #{count} signing #{'secret'.pluralize(count)} saved for #{integration.name}. Changes it sends no longer reach the map " \
      "until you add a secret again, and the map updates at each #{map_sweep_words}."
  end

  # Firefight registers, extends and removes the provider's webhook with the connection's own credentials, and no person
  # asked it to, so each call is in the activity log under the map sweep, as its reads are. change says which (register,
  # refresh or remove). Returns the block's result, and a call that fails is recorded with the provider's words.
  def record_map_events_webhook!(change, &)
    AbilityGateway.record_unattended!(
      principal: SystemAgent.map_sweep, action_key: MAP_EVENTS_WEBHOOK_ACTION_KEY, workspace: integration.workspace,
      params: { "webhook" => change, "connection" => integration.slug, "environment" => environment&.slug }.compact,
      context: { source: AbilityGateway::SOURCE_MAP_SWEEP, triggered_by_label: MAP_EVENTS_WEBHOOK_LABEL },
      rescued: ->(error) { Ability::Invocation.summary_of(error.message) }, &
    )
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
    return "#{integration.name} cannot register for its changes." unless source&.registers_for?(self)
    return "#{integration.name} is switched off. Switch it on first." unless integration.operational? && enabled?

    "#{live_updates_subject.upcase_first} are already on for #{integration.name}." if map_events_webhook_id.present?
  end

  # Why a person cannot turn live updates off, or nil. Only a connection a person decided on can be turned off, since
  # anywhere else Firefight's webhook costs the account nothing.
  def live_updates_turn_off_blocked_reason
    return "#{live_updates_subject.upcase_first} are already off for #{integration.name}." if map_events_webhook_id.blank?

    "Firefight's webhook costs #{integration.name} nothing, so live updates stay on while it is connected." if map_events_confirmation.blank?
  end

  # Nil for a provider Firefight cannot register a webhook with, whose live updates are not a switch.
  def live_updates_toggle
    return unless map_event_source&.registers_for?(self)

    if map_events_webhook_id.blank?
      Toggle.new(turns_on: true, words: live_updates_turn_on_words, blocked_reason: live_updates_turn_on_blocked_reason, subject: live_updates_subject)
    else
      Toggle.new(turns_on: false, words: live_updates_turn_off_words, blocked_reason: live_updates_turn_off_blocked_reason, subject: live_updates_subject)
    end
  end

  # What turning live updates on does, for the person about to, said before they confirm: what it gains, when the
  # provider says, then what it costs.
  def live_updates_turn_on_words
    gain = map_event_source&.turn_on_words
    return Integrations::Sentence.all(gain, map_events_confirmation) if gain
    return map_events_confirmation if map_events_confirmation.present?

    "Firefight adds a webhook to #{integration.name}, so its changes reach the map within about a minute."
  end

  def live_updates_turn_off_words
    source = map_event_source
    removed = source&.turn_off_words || "Firefight removes its webhook from #{integration.name}, which frees it for one of your own."
    return removed if source&.polls?

    Integrations::Sentence.all(removed, "Changes then reach the map at each #{map_sweep_words}")
  end

  # The toast once live updates were switched, saying what changed and what follows the provider's changes now.
  def live_updates_switched_words(on:)
    subject = live_updates_subject.upcase_first
    return "#{subject} are on. Changes #{integration.name} sends now reach the map." if on
    if map_event_source&.polls?
      return "#{subject} are off. Firefight removed its webhook from #{integration.name} and still checks for changes " \
             "every #{map_event_source.poll_every.inspect}."
    end

    "#{subject} are off. Firefight removed its webhook from #{integration.name}, and changes reach the map at each #{map_sweep_words}."
  end

  # Why turning live updates on did not work. A provider whose change log is read either way says it apart from the
  # log's own state.
  def live_updates_turn_on_failed_words
    state = live_updates
    refused = state.second_way&.reason
    refused ? "#{live_updates_subject.upcase_first} could not be turned on. #{refused}" : state.reason
  end

  def live_updates_turn_off_failed_words(error)
    return "#{live_updates_subject.upcase_first} could not be turned off. #{Integrations::Sentence.of(error)}" if map_event_source&.polls?

    Integrations::Sentence.join("Firefight could not remove its webhook from #{integration.name}", error)
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

  # For a provider whose change log is read, the other way its changes reach Firefight, when it has one: a webhook
  # Firefight registers when a person turns it on, or one an admin sets up by hand with a secret. A connection that is
  # switched off or stopped accepts nothing, so neither way reads as on then.
  def live_updates_second_way(source)
    name = source.deliveries_name
    return unless source.polls? && name

    reachable = integration.operational? && enabled? && !installation_stopped?
    if source.registers_for?(self)
      on = reachable && map_events_webhook_id.present? && !map_events_lapsed?
      line = if on then "#{name}: on"
      elsif reachable && map_events_registration_error.present? then "#{name} could not be turned on"
      else "#{name}: off"
      end
      return SecondWay.new(line: line, on: on, reason: (map_events_registration_error if reachable && !on))
    end
    return unless map_events_set_up_by_hand?

    SecondWay.new(line: map_events_secret_set? ? "#{name}: ready (secret saved)" : "#{name}: waiting for setup", on: reachable && map_events_secret_set?, reason: nil)
  end

  def live_updates_on?(source)
    return false unless integration.operational? && enabled?
    return false if installation_stopped?
    return true if source.polls? && map_events_error.blank?
    return map_events_sent_from.present? if source.offers?
    return installation_id.present? && Integrations::MapEvents.app_secret(integration.provider).present? if source.app_wide?
    return map_events_webhook_id.present? && !map_events_lapsed? if source.registers_for?(self)

    map_events_secret_set?
  end

  def live_updates_off_reason(source)
    name = integration.name
    sweep = map_sweep_words
    return "#{name} is switched off, so changes there do not reach the map." unless integration.operational? && enabled?
    return Integrations::Installations.live_updates_reason(self) if installation_stopped?
    # A provider whose change log is read as well keeps following it whether its registration is on or off.
    if source.registers_for?(self) && !source.polls? && map_events_turned_off_at.present?
      return "Changes reach the map at each #{sweep} until someone turns them on again."
    end
    if map_events_error.present?
      if source.offers? && map_events_sent_from.present?
        return Integrations::Sentence.join("Firefight could not read #{name}'s change log", map_events_error,
                                           after: "Changes still arrive as they happen from #{map_events_sent_from.keys.to_sentence}.")
      end
      after = map_events_refused_at ? "Firefight tries again tomorrow. The map still updates at each #{sweep}." : "The map still updates at each #{sweep}."
      return Integrations::Sentence.join("Firefight could not follow #{name}'s changes", map_events_error, after: after)
    end
    if source.registers_for?(self) && !source.polls? && map_events_webhook_id.blank? && map_events_confirmation.present?
      return "Firefight asks before adding its webhook to #{name}. #{map_events_confirmation}"
    end
    return if source.polls?

    if source.app_wide?
      app = "Firefight's #{ResourceMap.provider_name(integration.provider)} app"
      return "#{app} is not set up to send changes, so the map updates at each #{sweep}." if Integrations::MapEvents.app_secret(integration.provider).blank?

      return installation_id.present? ? nil : "#{name} was not connected through #{app}, so its changes reach the map at each #{sweep}."
    end
    return "#{name}'s registration for changes lapsed. Firefight registers again at the next sweep." if source.registers_for?(self) && map_events_lapsed?
    return "Firefight registers for #{name}'s changes at the next sweep." if source.registers_for?(self) && map_events_webhook_id.blank?

    return if source.registers_for?(self) || map_events_secret_set?

    Integrations::Sentence.all("Send #{name}'s changes to Firefight and save the signing secret under Integrations to turn them on", source.by_hand_note)
  end

  def map_events_lapsed? = map_events_expires_at.present? && map_events_expires_at <= Time.current
end
