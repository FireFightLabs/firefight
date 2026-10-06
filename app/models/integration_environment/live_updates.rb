# Whether what this connection reaches follows its provider's changes between sweeps (Integrations::MapEvents). Each
# row has its own address for the provider's events and the secret they are signed with, which Firefight keeps when it
# registered the webhook itself and an admin pastes when the provider is set up by hand.
module IntegrationEnvironment::LiveUpdates
  extend ActiveSupport::Concern

  # What a person reads about live updates on one connection. on says whether changes reach the map between sweeps,
  # last_event_at when the provider last said something changed, and reason why they do not, or what is wrong with one
  # of two ways in while the other still works.
  State = Data.define(:on, :last_event_at, :reason)

  included do
    encrypts :map_events_secret
    normalizes :map_events_secret, with: ->(value) { value.to_s.strip.presence }
  end

  def map_event_source = Integrations::Provider.for(integration.provider).map_events

  # nil for a provider that cannot say what changed, whose connection is read at each sweep only.
  def live_updates
    source = map_event_source
    return unless source

    reason = live_updates_off_reason(source)
    State.new(on: live_updates_on?(source), last_event_at: map_events_received_at, reason: reason)
  end

  # Whether an admin sends the provider's changes to the connection's address and pastes the signing secret.
  def map_events_set_up_by_hand? = map_event_source.then { |source| source.present? && source.setup_steps.any? && !source.registers? }

  def map_events_secret_set? = map_events_secret.present?

  # The secret an admin pasted from the provider. Saving it again replaces it.
  def save_map_events_secret!(secret)
    update!(map_events_secret: secret, map_events_error: nil)
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
    return installation_id.present? && Integrations::MapEvents.app_secret(integration.provider).present? if source.app_wide?
    return map_events_webhook_id.present? && !map_events_lapsed? if source.registers?

    map_events_secret_set?
  end

  def live_updates_off_reason(source)
    name = integration.name
    return "#{name} is switched off, so changes there do not reach the map." unless integration.operational? && enabled?
    if map_events_error.present?
      return Integrations::Sentence.join("Firefight could not follow #{name}'s changes", map_events_error, after: "The map still updates at each sweep.")
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
