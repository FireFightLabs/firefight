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

  CONNECT_WITH_UNION = IntegrationProvider::CONNECT_WITH.map(&:inspect).join(" | ")

  type CONNECT_WITH_UNION, optional: true
  def connect_with
    provider.connect_with
  end

  # What the connect form asks for when a provider connects with credentials, as the provider's pack declares it.
  type "{ key: string; label: string; hint: string; placeholder: string; secret: boolean }[]"
  def credential_fields
    return [] unless provider.api_token?

    Integrations::NativePack.for(provider.key)&.credential_fields.to_a.map(&:to_h)
  end
end
