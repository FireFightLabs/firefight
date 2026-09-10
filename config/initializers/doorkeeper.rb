# OAuth 2.1 for MCP clients. The resource owner is a WorkspaceMembership, the same principal
# a personal API key resolves to, so this issues tokens rather than adding a second permission model.
Doorkeeper.configure do
  orm :active_record

  # The membership is looked up through the signed-in user's own memberships, which is what
  # keeps workspace_id unforgeable.
  resource_owner_authenticator do
    user = session[:user_id] && User.find_by(id: session[:user_id])
    membership = user && (user.workspace_memberships.find_by(workspace_id: params[:workspace_id]) ||
                          user.workspace_memberships.find_by(workspace_id: session[:workspace_id]) ||
                          user.workspace_memberships.order(joined_at: :desc).first)

    unless membership
      session[:return_to] = request.fullpath
      redirect_to login_path, alert: "Sign in to connect an agent"
    end

    membership
  end

  grant_flows %w[authorization_code]
  force_pkce
  pkce_code_challenge_methods %w[S256]

  access_token_expires_in 2.hours
  use_refresh_token

  default_scopes :"mcp:read"
  enforce_configured_scopes

  # Native MCP clients receive the code on a localhost listener, exempt from TLS by RFC 8252 7.3.
  force_ssl_in_redirect_uri do |uri|
    !Rails.env.local? && !%w[ localhost 127.0.0.1 ::1 ].include?(uri.hostname)
  end

  hash_token_secrets
  hash_application_secrets

  base_controller "ActionController::Base"
end
