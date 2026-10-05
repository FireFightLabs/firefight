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

  # What the connect form asks beside the credentials, as the registry declares it. A path field is part of the server's
  # address, so the form for a pasted address does not ask it.
  # A field with options is a choice from them, and one marked multiple holds several. allowed says what a value may hold.
  # Fields chosen after connecting are not asked here. address says a field is part of the server's address, which the
  # form for a pasted address does not ask.
  type "{ key: string; label: string; hint: string; placeholder: string; numeric: boolean; optional: boolean; address: boolean; allowed: string | null; options: { value: string; label: string }[]; multiple: boolean; default: string | null }[]"
  def connect_fields
    provider.connect_fields.reject(&:learned).map do |field|
      field.to_h.slice(:key, :label, :hint, :placeholder, :numeric, :optional, :allowed, :multiple, :default)
           .merge(address: field.address?, options: field.options.map(&:to_h))
    end
  end

  # Whether the connect form offers the provider's own MCP server beside its credentials.
  type :boolean
  def mcp_alternative = provider.mcp_alternative?
end
