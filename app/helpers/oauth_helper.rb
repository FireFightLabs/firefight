module OauthHelper
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
