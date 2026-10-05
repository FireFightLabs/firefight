module Integrations
  # What a provider's code may know about one connection's environment, without holding the row: the workspace, the
  # server it reaches, the region it was made in, what the connect form asked, and what its health check learned. Adapters,
  # readers, probes and link builders are handed this, so none of them reads a column or a settings key, and the way a
  # connection keeps these can change without touching any provider.
  class ConnectionSettings
    def self.of(environment_row) = new(environment_row)

    def initialize(environment_row)
      @row = environment_row
      @integration = environment_row.integration
    end

    def workspace = @integration.workspace

    def provider_key = @integration.provider

    # The connection's name as a person gave it, such as "Datadog EU".
    def name = @integration.name

    # The MCP server the connection reaches, nil for a native pack.
    def server_url = @integration.server_url

    # The region the connection was made in (Integration#region), nil when its provider lists none or a pasted
    # address is in none of them.
    def region = @integration.region

    # The address of the provider's app the connection is in, which links open. It is the region's site, or the registry's
    # site for a provider that runs in one place. nil when neither is known.
    def site = region&.site || IntegrationProvider.find(provider_key)&.site

    # What the connect form asked, by the field's key, for this environment or the whole connection, or the field's
    # default when it was left empty, or nil. A field that holds several values answers a list.
    def field(key)
      @row.fields[key.to_s].presence || @integration.address_fields[key.to_s].presence ||
        IntegrationProvider.find(provider_key)&.connect_fields&.find { |each| each.key == key.to_s }&.default
    end

    # Every site the provider's regions have, for a link builder that recognises an address on any of them.
    def region_sites = IntegrationProvider.find(provider_key)&.regions.to_a.filter_map(&:site)

    # Keeps a value a pack or its client caches with the credentials, such as a short-lived access token it minted, read
    # back with credential. The cache's shape is the pack's own.
    def store_credential!(key, value) = @row.store_credential!(key.to_s, value)

    # A value a native pack stored with its credentials (NativePack.store_credentials!), such as an API token, or nil.
    # Only the pack that stored it reads it, to call its provider. It never reaches the model, a chat, an MCP response
    # or the ledger.
    def credential(key) = @row.credentials_hash[key.to_s].presence

    # What the provider's health check learned about this environment, as the probe wrote it.
    def learned = @row.learned

    def environment_id = @row.catalog_entry_id
  end
end
