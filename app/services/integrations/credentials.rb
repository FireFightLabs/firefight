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

      credentials = refreshed(environment_row) if OauthClient.stale?(credentials)
      { "Authorization" => "Bearer #{OauthClient.access_token(credentials)}" }
    end

    # Two callers may find a token stale at once, and a provider that rotates refresh tokens takes each only once, so the
    # row is locked and read again, and only the first refreshes it. A refresh token the provider no longer takes, such
    # as one past the time it keeps a sign-in for, fails the connection's health with how to sign in again.
    def self.refreshed(environment_row)
      environment_row.with_lock do
        current = environment_row.oauth
        OauthClient.stale?(current) ? environment_row.rotate_oauth!(OauthClient.refresh(current)) : current
      end
    rescue OauthClient::SignInEnded
      name = environment_row.integration.name
      raise OauthClient::SignInEnded, "The sign-in to #{name} has ended, so Firefight can no longer reach it. Open its details, choose Add " \
                                      "connection and sign in again under the name #{name}."
    end
    private_class_method :refreshed

    # The fields the connect form asks a provider connected with credentials for (NativePack::CredentialField).
    def self.fields_for(provider_key) = NativePack.for(provider_key)&.credential_fields.to_a

    # The placeholder and hint the connect form shows for a provider connected from a pasted URL, or nil.
    def self.connection_url_words_for(provider_key) = NativePack.for(provider_key)&.connection_url_words

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

    # Why the installation an install flow came back with cannot be connected, or nil when the person manages it.
    def self.installation_refusal(provider_key, installation_id, code:, redirect_uri:)
      pack!(provider_key).installation_refusal(installation_id, code: code, redirect_uri: redirect_uri)
    end

    def self.pack!(provider_key)
      NativePack.for(provider_key) || raise(NativePack::Error, "#{provider_key} has no native pack, so it does not connect this way")
    end
    private_class_method :pack!
  end
end
