# OAuth 2.1 provider for MCP clients (Claude Code, claude.ai connectors, …).
# The resource owner is a WorkspaceMembership — the same principal personal
# API tokens resolve to — so OAuth is an issuance flow, not a second
# authorization system. Clients register via our RFC 7591 endpoint as public
# clients and must use PKCE.
Doorkeeper.configure do
  orm :active_record

  # The consent screen requires a signed-in Slack session; the owner is the
  # user's membership in their currently selected workspace.
  resource_owner_authenticator do
    user = session[:user_id] && User.find_by(id: session[:user_id])
    workspace = user && (user.workspaces.find_by(id: session[:workspace_id]) ||
                         user.workspace_memberships.order(joined_at: :desc).first&.workspace)
    membership = workspace && workspace.workspace_memberships.find_by(user: user)

    unless membership
      session[:return_to] = request.fullpath
      redirect_to login_path, alert: "Sign in to connect an agent"
    end

    membership
  end

  # OAuth 2.1: authorization code only (no implicit/password), PKCE required,
  # S256 only (the spec deprecates "plain").
  grant_flows %w[authorization_code]
  force_pkce
  pkce_code_challenge_methods %w[S256]

  # Short-lived access tokens with refresh rotation.
  access_token_expires_in 2.hours
  use_refresh_token

  default_scopes :"mcp:read"
  enforce_configured_scopes

  # HTTPS everywhere except loopback: native MCP clients (Claude Code) receive
  # the code on a localhost listener, which RFC 8252 §7.3 exempts from TLS.
  force_ssl_in_redirect_uri do |uri|
    !Rails.env.local? && !%w[ localhost 127.0.0.1 ::1 ].include?(uri.hostname)
  end

  # Tokens are hashed at rest, matching the ApiKey digest posture.
  hash_token_secrets
  hash_application_secrets

  base_controller "ActionController::Base"
end
