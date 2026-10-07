module Integrations
  # A connection's credentials, the one way in for anything outside the integrations layer. OAuth credentials rotate when
  # close to expiry, and the rotation is persisted before it is used. A native pack that connects another way owns the
  # shape of what it asks for and keeps, so the connect form and its controller ask through here and never name a pack:
  # the fields it asks (connect_with: api_token), a pasted connection URL and its certificates (connect_with:
  # connection_url), or the install screen of an app (install first).
  class Credentials
    def self.headers_for(environment_row)
      return {} unless environment_row

      credentials = environment_row.oauth
      return environment_row.request_headers if credentials.blank?

      credentials = environment_row.rotate_oauth!(OauthClient.refresh(credentials)) if OauthClient.stale?(credentials)
      { "Authorization" => "Bearer #{OauthClient.access_token(credentials)}" }
    end

    # The fields the connect form asks a provider connected with credentials for (NativePack::CredentialField).
    def self.fields_for(provider_key) = NativePack.for(provider_key)&.credential_fields.to_a

    # Why the values cannot be used, read with the provider before anything is saved, or nil. region is the
    # IntegrationProvider::Region chosen, or nil for a provider that lists none, and fields what the form asked beside
    # the credentials.
    def self.refusal(provider_key, values, region: nil, fields: {})
      pack!(provider_key).credential_refusal(values, region: region, fields: fields)
    end

    def self.store!(environment_row, values) = pack!(environment_row.integration.provider).store_credentials!(environment_row, values)

    # The scopes credentials can read for a provider whose connect form chooses them (IntegrationProvider::ConnectField,
    # scope), such as the projects an API token reaches, listed from the provider before anything is saved. Each is an
    # IntegrationProvider::ConnectOption. Raises the provider's refusal in its words.
    def self.scope_options(provider_key, values, region: nil, fields: {})
      pack!(provider_key).scope_options(values, region: region, fields: fields)
    end

    # The same for a connection already made, with the credentials it keeps.
    def self.scope_options_of(settings) = pack!(settings.provider_key).scope_options_of(settings)

    # The certificates a provider connected from a pasted URL may be given, pasted as text.
    def self.certificate_fields(provider_key) = NativePack.for(provider_key)&.certificate_fields.to_a

    def self.url_refusal(provider_key, url, certificates) = pack!(provider_key).connection_refusal(url, certificates)

    def self.store_url!(environment_row, url:, certificates:)
      pack!(environment_row.integration.provider).store_connection!(environment_row, url: url, certificates: certificates)
    end

    # Where to send a person to install a provider's app, for a provider that gates access behind one, or nil.
    def self.install_url(provider_key, state:) = NativePack.for(provider_key)&.install_url(state: state)

    def self.pack!(provider_key)
      NativePack.for(provider_key) || raise(NativePack::Error, "#{provider_key} has no native pack, so it does not connect this way")
    end
    private_class_method :pack!
  end
end
