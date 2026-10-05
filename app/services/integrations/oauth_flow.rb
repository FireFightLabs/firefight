module Integrations
  module OauthFlow
    Error = OauthClient::Error

    # server_url is the server the connection will call, which the token is asked for. region is the key of the
    # provider's region chosen on the connect form, whose OAuth endpoints are used where it lists its own.
    def self.begin(provider, redirect_uri:, server_url: provider.server_url, region: nil)
      endpoints = provider.region(region).to_h.slice(:authorization_endpoint, :token_endpoint).compact
      OauthClient.begin_flow(
        server_url: server_url, redirect_uri: redirect_uri,
        client_id: IntegrationProvider.oauth_client(provider.key)[:client_id], endpoints: endpoints
      )
    end

    # Firefight's own app with the provider (IntegrationProvider::App), for a native connection.
    def self.begin_app(provider, redirect_uri:)
      app = provider.app
      OauthClient.begin_app_flow(
        authorization_endpoint: app.authorization_endpoint, token_endpoint: app.token_endpoint,
        client_id: IntegrationProvider.app_client(provider.key)[:client_id], scope: app.scope, redirect_uri: redirect_uri,
        params: app.params, pkce: app.pkce
      )
    end

    def self.exchange_app(provider, pending, code:, redirect_uri:)
      OauthClient.exchange(
        token_endpoint: pending["token_endpoint"], code: code, verifier: pending["verifier"], client_id: pending["client_id"],
        client_secret: IntegrationProvider.app_client(provider.key)[:client_secret], redirect_uri: redirect_uri, resource: nil,
        json: provider.app.json_token?
      )
    end

    def self.exchange(provider, pending, code:, redirect_uri:)
      OauthClient.exchange(
        token_endpoint: pending["token_endpoint"], code: code,
        verifier: pending["verifier"], client_id: pending["client_id"],
        client_secret: IntegrationProvider.oauth_client(provider.key)[:client_secret],
        redirect_uri: redirect_uri, resource: pending["server_url"].presence || provider.server_url
      )
    end
  end
end
