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

    # The connection's own id, which never changes, for a reader keying something by the connection when the provider
    # names no account.
    def connection_id = @integration.id

    # The connection's name as a person gave it, such as "Datadog EU".
    def name = @integration.name

    # How a person tells the connection apart from another to the same provider, such as "Faylee (Northflank)".
    def display_name = @integration.display_name

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

    # The app installation the connection was made through, such as a GitHub App's, or nil.
    def installation_id = @row.installation_id

    # What the provider's health check learned about this environment, as the probe wrote it.
    def learned = @row.learned

    # The connect field that names what the connection reads at the provider, such as Northflank's projects, or nil for
    # a provider that names none (IntegrationProvider::ConnectField, scope).
    def scope_field = IntegrationProvider.find(provider_key)&.scope_field

    # What the connect form chose for it, the scopes by their ids, or ConnectField::ALL alone for every one the
    # credential can read. A value kept as one string from before reads as a list of it.
    def chosen_scopes = scope_field ? Array(field(scope_field.key)).map(&:to_s).compact_blank : []

    def all_scopes? = chosen_scopes == [ IntegrationProvider::ConnectField::ALL ]

    # Whether the connection may reach more than one scope, read without asking the provider.
    def several_scopes? = all_scopes? || chosen_scopes.size > 1

    # Every scope the connection reaches, by its id. ALL is listed from the credential now, so a project added since is
    # read at the next sweep. Raises the provider's error when it cannot be listed.
    def scopes
      @scopes ||= all_scopes? ? scope_options.map(&:value) : chosen_scopes
    end

    # The scopes the credential can read, listed from the provider now, each with its id and its name
    # (IntegrationProvider::ConnectOption). Kept with what the connection learned, so a tool's parameters and a person
    # reading the connection name them without asking the provider again.
    def scope_options
      @scope_options ||= Credentials.scope_options_of(self).tap do |options|
        listed = options.map(&:to_h).map(&:stringify_keys)
        @row.store_learned!(learned.merge(SCOPES_LEARNED => listed)) unless learned[SCOPES_LEARNED] == listed
      end
    end

    SCOPES_LEARNED = "scopes".freeze

    # The scopes the connection reaches as last listed, without asking the provider. That is what was chosen, or for ALL what
    # the last listing found.
    def known_scopes = all_scopes? ? Array(learned[SCOPES_LEARNED]).filter_map { |option| option["value"].presence if option.is_a?(Hash) } : chosen_scopes

    # A scope's name as the provider gives it, or its id when no listing named it.
    def scope_name(id)
      Array(learned[SCOPES_LEARNED]).find { |option| option.is_a?(Hash) && option["value"] == id.to_s }&.dig("label").presence || id.to_s
    end

    def environment_id = @row.catalog_entry_id
  end
end
