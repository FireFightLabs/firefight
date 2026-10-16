module OauthHelper
  # What each scope lets a client do, in the words the consent screen shows. mcp:read is the one scope Firefight issues,
  # and a token holding it acts as the person through the MCP server with their own reach.
  SCOPE_WORDS = {
    "mcp:read" => "Use Firefight's tools as you, reading what you can read and making the changes you can make. Every call " \
                  "is in the activity log and follows your workspace's approval rules."
  }.freeze
  LOOPBACK_HOSTS = %w[localhost 127.0.0.1 ::1].freeze

  # Where the browser goes once the person decides, so a client that registered someone else's address shows it here.
  def oauth_destination(pre_auth)
    uri = URI.parse(pre_auth.redirect_uri.to_s)
    return pre_auth.redirect_uri.to_s if uri.host.blank?

    host = uri.port && uri.port != uri.default_port ? "#{uri.host}:#{uri.port}" : uri.host.to_s
    return "an app on this computer (#{host})" if LOOPBACK_HOSTS.include?(uri.hostname)

    host
  rescue URI::InvalidURIError
    pre_auth.redirect_uri.to_s
  end

  def oauth_scope_words(pre_auth)
    pre_auth.scopes.map { |scope| SCOPE_WORDS.fetch(scope.to_s, scope.to_s) }
  end

  # Exactly the set the resource owner authenticator will accept.
  def oauth_consent_memberships(membership)
    membership.user.workspace_memberships.joins(:workspace).includes(:workspace).order("workspaces.name")
  end

  def oauth_workspace_options(membership, memberships)
    options_for_select(memberships.map { |option| [ option.workspace.name, option.workspace_id ] }, membership.workspace_id)
  end

  # Doorkeeper re-validates the exact authorization request, PKCE challenge
  # included, so both consent forms round-trip these.
  def oauth_pre_auth_fields(pre_auth)
    {
      client_id: pre_auth.client.uid,
      redirect_uri: pre_auth.redirect_uri,
      state: pre_auth.state,
      response_type: pre_auth.response_type,
      response_mode: pre_auth.response_mode,
      scope: pre_auth.scope,
      code_challenge: pre_auth.code_challenge,
      code_challenge_method: pre_auth.code_challenge_method
    }
  end
end
