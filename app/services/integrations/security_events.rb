module Integrations
  # What a connected provider reports that the security module looks into, in one shape whichever provider sent it. A
  # provider's event source may answer security_events(payload, headers:) with Events, so a delivery that says a secret
  # leaked reaches Halon at once. Nothing here names a provider.
  module SecurityEvents
    KIND_LEAKED_SECRET = "leaked_secret".freeze
    KINDS = [ KIND_LEAKED_SECRET ].freeze

    # One report: what kind, the provider's own reference for it (unique within the provider, such as a repository and an
    # alert number), the repository or account it is in, what leaked in the provider's words, the provider's page for it,
    # and whether it is known to be public.
    Event = Data.define(:kind, :provider, :reference, :place, :what, :url, :public) do
      def initialize(url: nil, public: false, **) = super
    end

    module_function

    # What a delivery to a connection says about security, through its provider's event source, or none.
    def of(provider_key, payload, headers:)
      source = MapEvents.source_of(provider_key)
      return [] unless source.respond_to?(:security_events)

      Array(source.security_events(payload, headers: headers))
    rescue StandardError => error
      Rails.logger.warn({ event: "security_events.unread", provider: provider_key, error: error.class.name }.to_json)
      []
    end
  end
end
