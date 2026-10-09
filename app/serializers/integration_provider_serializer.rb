class IntegrationProviderSerializer < BaseSerializer
  object_as :provider

  KIND_UNION = Integration::KINDS.map(&:inspect).join(" | ")

  attributes(
    key: { type: :string },
    name: { type: :string },
    category: { type: :string },
    mark: { type: :string },
    color: { type: :string },
    description: { type: :string },
    server_url: { type: :string }
  )

  type KIND_UNION
  def kind
    provider.kind
  end

  # What Halon can do through the provider, said in its details.
  type :string
  def halon = Integrations::Capabilities.halon_sentence(provider.key, provider.name)

  # Whether what the provider runs is read onto the resource map.
  type :boolean
  def on_map = provider.map == IntegrationProvider::MAP_FIREFIGHT

  CONNECT_WITH_UNION = IntegrationProvider::CONNECT_WITH.map(&:inspect).join(" | ")

  type CONNECT_WITH_UNION, optional: true
  def connect_with
    provider.connect_with
  end

  # What the connect form asks for when a provider connects with credentials, as the provider's pack declares it.
  type "{ key: string; label: string; hint: string; placeholder: string; secret: boolean; optional: boolean; multiline: boolean }[]"
  def credential_fields
    return [] unless provider.api_token?

    Integrations::Credentials.fields_for(provider.key).map(&:to_h)
  end

  # Where the provider runs its service, which the connect dialog asks only when there is more than one.
  type "{ key: string; label: string; serverUrl: string }[]"
  def regions = provider.regions.map { |region| { key: region.key, label: region.label, serverUrl: region.server_url } }

  # What the connect form asks beside the credentials, as the registry declares it.
  # A field with options is a choice from them, and one marked multiple holds several. allowed says what a value may hold.
  # Fields chosen after connecting are not asked here. address says a field is part of the server's address, which the
  # form for a pasted address does not ask.
  # scope says a field names what the connection reads, such as projects, listed live from the credentials typed
  # (list_scopes), and holding one, several or every one they can read.
  type "{ key: string; label: string; hint: string; placeholder: string; numeric: boolean; optional: boolean; address: boolean; allowed: string | null; options: { value: string; label: string }[]; multiple: boolean; default: string | null; scope: boolean }[]"
  def connect_fields
    provider.connect_fields.reject(&:learned).map do |field|
      field.to_h.slice(:key, :label, :hint, :placeholder, :numeric, :optional, :allowed, :multiple, :default, :scope)
           .merge(address: field.address?, options: field.options.map(&:to_h))
    end
  end

  # Whether the connect form offers the provider's own MCP server beside its credentials.
  type :boolean
  def mcp_alternative = provider.mcp_alternative?

  # Firefight's own app with the provider, which connects it to keep incident items in step with issues, or null when
  # the provider has none or this install did not register it.
  type "{ label: string, description: string, connectionName: string } | null"
  def app = provider.app_connect? ? { label: provider.app.label, description: provider.app.description, connectionName: provider.app.connection_name } : nil

  # What the connect form shows under the URL field of a provider connected from a pasted URL, or null.
  type "{ placeholder: string, hint: string } | null"
  def connection_url = Integrations::Credentials.connection_url_words_for(provider.key)
end
