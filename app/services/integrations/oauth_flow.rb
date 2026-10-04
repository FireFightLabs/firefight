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
