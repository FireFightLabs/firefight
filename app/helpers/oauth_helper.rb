module OauthHelper
  # Every workspace the consenting member could grant, so the picker offers
  # exactly the set the resource owner authenticator will accept.
  def oauth_consent_memberships(membership)
    membership.user.workspace_memberships.joins(:workspace).includes(:workspace).order("workspaces.name")
  end

  def oauth_workspace_options(membership, memberships)
    options_for_select(memberships.map { |option| [ option.workspace.name, option.workspace_id ] }, membership.workspace_id)
  end

  # The hidden fields both consent forms must round-trip so Doorkeeper can
  # re-validate the exact authorization request (incl. PKCE challenge).
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
