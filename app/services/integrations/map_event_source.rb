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
  #   register(row, url:)                     registers a webhook itself, answering a Webhook
  #   refresh(row, webhook_id)                extends one that lapses, answering when it now does
  #   remove(row, webhook_id)                 takes it back while the connection's credentials still reach the provider
  #   poll(row, since:)                       reads the provider's change log after the cursor since (nil the first time,
  #                                           when it starts from now), answering a Polled
  #   installation_of(payload, headers:)      for a provider that sends every connection's changes to one address for its
  #                                           app, the installation they are about, matched to a connection's own
  #                                           (IntegrationEnvironment#installation_id). The delivery is verified with
  #                                           the app's secret, INTEGRATION_<KEY>_WEBHOOK_SECRET.
  # One provider may both poll and be sent changes on the same connection. An event read both ways carries the same id,
  # so it is read again once.
  class MapEventSource
    # A webhook Firefight registered. secret is what it signs with, nil when the provider signs another way, and
    # expires_at when it lapses unless refreshed.
    Webhook = Data.define(:id, :secret, :expires_at) do
      def initialize(id:, secret: nil, expires_at: nil) = super
    end

    # What one read of a change log found, and where the next read starts.
    Polled = Data.define(:events, :cursor)

    class << self
      def verify(raw_body:, headers:, secret:)
        raise NotImplementedError, "#{name} does not say how its deliveries are signed"
      end

      def events(_payload, headers:)
        raise NotImplementedError, "#{name} does not read its deliveries"
      end

      def setup_steps = []

      def registers? = respond_to?(:register)

      def polls? = respond_to?(:poll)

      def app_wide? = respond_to?(:installation_of)
    end
  end
end
