module Integrations
  # The one-click connect handshake, so the controller only holds what the
  # session needs between the redirect out and the callback in.
  module OauthFlow
    Error = OauthClient::Error

    def self.begin(provider, redirect_uri:)
      OauthClient.begin_flow(
        server_url: provider.server_url, redirect_uri: redirect_uri,
        client_id: IntegrationProvider.oauth_client(provider.key)[:client_id]
      )
    end

    def self.exchange(provider, pending, code:, redirect_uri:)
      OauthClient.exchange(
        token_endpoint: pending["token_endpoint"], code: code,
        verifier: pending["verifier"], client_id: pending["client_id"],
        client_secret: IntegrationProvider.oauth_client(provider.key)[:client_secret],
        redirect_uri: redirect_uri, resource: provider.server_url
      )
    end
  end
end
