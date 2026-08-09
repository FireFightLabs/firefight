module Integrations
  # Provider key -> pack class. A provider listed here executes through its
  # pack instead of an MCP server; its registry entry declares kind: native
  # so the connect flow skips the server URL. Listing and execution stay
  # decoupled on purpose - the gallery is config, the pack is code.
  class NativePacks
    REGISTRY = {}.freeze

    def self.for(provider_key)
      REGISTRY[provider_key.to_s]&.constantize
    end

    def self.fetch!(integration)
      pack_class = self.for(integration.provider)
      raise NativePack::Error, "No native pack registered for '#{integration.provider}'" unless pack_class

      pack_class.new(integration)
    end
  end
end
