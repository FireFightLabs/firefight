# OAuth discovery documents MCP clients use to find the authorization server
# (RFC 8414) and to learn this resource requires it (RFC 9728).
class Oauth::MetadataController < ActionController::API
  def authorization_server
    render json: {
      issuer: root_url.chomp("/"),
      authorization_endpoint: oauth_authorization_url,
      token_endpoint: oauth_token_url,
      registration_endpoint: oauth_register_url,
      revocation_endpoint: oauth_revoke_url,
      scopes_supported: Doorkeeper.config.scopes.to_a,
      response_types_supported: [ "code" ],
      grant_types_supported: [ "authorization_code", "refresh_token" ],
      code_challenge_methods_supported: [ "S256" ],
      token_endpoint_auth_methods_supported: [ "none" ]
    }
  end

  def protected_resource
    render json: {
      resource: mcp_url,
      authorization_servers: [ root_url.chomp("/") ],
      scopes_supported: Doorkeeper.config.scopes.to_a,
      bearer_methods_supported: [ "header" ]
    }
  end
end
