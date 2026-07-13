# Registry for inbound alert provider adapters — the inbound mirror of the
# platform adapter layer. Each adapter verifies a request and normalizes the
# provider payload into an array of Alert field hashes.
module AlertProviders
  ADAPTERS = {
    AlertSource::PROVIDER_GENERIC => "AlertProviders::Generic"
  }.freeze

  def self.for(provider)
    class_name = ADAPTERS.fetch(provider) do
      raise ArgumentError, "unknown alert provider: #{provider.inspect}"
    end
    class_name.constantize
  end
end
