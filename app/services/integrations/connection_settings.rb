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

    # What the connect form asked, by the field's key, for this environment or the whole connection, or nil.
    def field(key) = @row.fields[key.to_s].presence || @integration.path_fields[key.to_s].presence

    # What the provider's health check learned about this environment, as the probe wrote it.
    def learned = @row.learned

    def environment_id = @row.catalog_entry_id
  end
end
