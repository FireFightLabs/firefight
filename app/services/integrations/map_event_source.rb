module Integrations
  # The map_events part of a provider's definition (Integrations::Provider): how its changes reach Firefight, so the
  # map follows them within about a minute instead of waiting for the next sweep. A provider's own source lives in
  # map_event_sources/<key>.rb and subclasses this one, answering on its class side.
  #
  # Every source answers, for a delivery to a connection's own address:
  #   verify(raw_body:, headers:, secret:)    whether the delivery is the provider's own, checked as it documents
  #   events(payload, headers:)               the ResourceMap::Events it holds, empty for anything else
  # and may answer:
  #   setup_steps                             sentences saying how an admin sends the provider's changes to the
  #                                           connection's address, for a provider Firefight cannot register with
  #   register(row, url:)                     registers a webhook itself, answering a Webhook, and raises Refused when
  #                                           the provider turns it down for its plan or a limit
  #   confirmation_for(row, url:)             a sentence saying what registering would cost the account, such as its
  #                                           only webhook, when a person should decide first, or nil
  #   register_again?(row, url:)              whether a registration from before no longer covers what the connection
  #                                           reaches, for a provider whose webhooks are one per resource, such as a
  #                                           resource added since or a webhook the provider switched off. Asked with
  #                                           each hourly sweep, and registering again is safe, since register takes
  #                                           back what it finds at the address
  #   refresh(row, webhook_id)                extends one that lapses, answering when it now does
  #   remove(row, webhook_id)                 takes it back while the connection's credentials still reach the provider
  #   poll(row, since:)                       reads the provider's change log after the cursor since (nil the first time,
  #                                           when it starts from now), answering a Polled
  #   limits                                  a sentence saying what live updates do not follow, such as a resource
  #                                           added or its settings changing, which the hourly sweep reads, shown on
  #                                           the connection while they are on
  #   installation_of(payload, headers:)      for a provider that sends every connection's changes to one address for its
  #                                           app, the installation they are about, matched to a connection's own
  #                                           (IntegrationEnvironment#installation_id). The delivery is verified with
  #                                           the app's secret, INTEGRATION_<KEY>_WEBHOOK_SECRET.
  #   offers(row)                             for a provider a person sets up to send changes, from a template Firefight
  #                                           made, the places they may set it up in (Offer), such as a cloud's regions,
  #                                           with offer_words (what setting it up does), offer_action (the button),
  #                                           offer_unavailable_reason (nil, or why no link can be made),
  #                                           offer_link(row, place:, url:, secret:) (the provider's own page for it, the
  #                                           secret being one Firefight made for the connection), delivery_place(payload)
  #                                           and delivery_ends?(payload) (where a delivery came from, and whether it says
  #                                           that place's setup is being removed) and removal_words(row, places) (how a
  #                                           person removes what they set up, which Firefight cannot)
  # One provider may both poll and be sent changes on the same connection. An event read both ways carries the same id,
  # so it is read again once.
  class MapEventSource
    # A webhook Firefight registered. secret is what it signs with, nil when the provider signs another way, and
    # expires_at when it lapses unless refreshed.
    Webhook = Data.define(:id, :secret, :expires_at) do
      def initialize(id:, secret: nil, expires_at: nil) = super
    end

    # The provider turned a registration down for the account's plan or a limit, which a retry within the day would not
    # change.
    class Refused < Integrations::Error; end

    # What one read of a change log found, and where the next read starts.
    Polled = Data.define(:events, :cursor)

    # A place a person may set the provider up to send changes from, by its key and the name a person reads, with why it
    # cannot be set up there, or nil.
    Offer = Data.define(:place, :label, :unavailable) do
      def initialize(place:, label:, unavailable: nil) = super
    end

    class << self
      def verify(raw_body:, headers:, secret:)
        raise NotImplementedError, "#{name} does not say how its deliveries are signed"
      end

      def events(_payload, headers:)
        raise NotImplementedError, "#{name} does not read its deliveries"
      end

      def setup_steps = []

      def limits = nil

      def registers? = respond_to?(:register)

      def asks_first? = respond_to?(:confirmation_for)

      def polls? = respond_to?(:poll)

      def app_wide? = respond_to?(:installation_of)

      def offers? = respond_to?(:offers)
    end
  end
end
