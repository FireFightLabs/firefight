require "net/http"

# Signing an AI account in with the provider's own OAuth, such as Sign in with ChatGPT, behind
# FeatureFlags::CHATGPT_SIGN_IN. A plain authorization code flow with PKCE, whose addresses all come from the
# environment (AiProviders::SignIn), so nothing about the provider's endpoint is assumed. The tokens it gets are the
# account's credentials, kept like a key and refreshed before they expire.
class AiAccountSignIn
  class Failed < StandardError; end

  TIMEOUT = 15

  def initialize(workspace, by: nil)
    @workspace = workspace
    @by = by
  end

  # Where to send the admin, and what to keep until they come back: the state to compare and the PKCE verifier.
  def begin(redirect_uri:)
    provider = AiProviders.sign_in_for(@workspace) || raise(Failed, "Signing in to an AI account is not available here.")
    sign_in = provider.sign_in
    state = SecureRandom.hex(16)
    verifier = SecureRandom.urlsafe_base64(48)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    query = { response_type: "code", client_id: sign_in.client_id, redirect_uri: redirect_uri, state: state,
              scope: sign_in.scopes.join(" ").presence, code_challenge: challenge, code_challenge_method: "S256" }.compact
    { url: "#{sign_in.authorize_url}?#{query.to_query}", pending: { "provider" => provider.slug, "state" => state, "verifier" => verifier } }
  end

  def finish!(pending, code:, state:, redirect_uri:)
    raise Failed, "That sign in expired. Start it again." unless pending.present? &&
                                                               ActiveSupport::SecurityUtils.secure_compare(pending["state"].to_s, state.to_s)

    provider = AiProviders.find(pending["provider"])
    sign_in = provider&.sign_in
    raise Failed, "Signing in to an AI account is not available here." unless sign_in&.configured? && AiProviders.sign_in_for(@workspace)

    tokens = token_request(sign_in, grant_type: "authorization_code", code: code, redirect_uri: redirect_uri, code_verifier: pending["verifier"])
    WorkspaceAiAccountService.new(@workspace, by: @by).connect_oauth!(
      provider: provider.slug, tokens: tokens.slice("access_token", "refresh_token"), expires_at: expires_at(tokens), email: email(tokens)
    )
  end

  def refresh!(account)
    sign_in = account.provider_definition&.sign_in
    refresh_token = account.token("refresh_token")
    raise Failed, "Sign in again to keep using this account." unless sign_in&.configured? && refresh_token.present?

    tokens = token_request(sign_in, grant_type: "refresh_token", refresh_token: refresh_token)
    account.store_tokens!({ "access_token" => tokens["access_token"], "refresh_token" => tokens["refresh_token"].presence || refresh_token },
                          expires_at: expires_at(tokens))
  rescue Failed => e
    account.key_refused!(FirefightAi::TerminalError.new(e.message, reason: AiAccountError::KEY_REASONS.first))
  end

  private

  def token_request(sign_in, **params)
    uri = URI.parse(sign_in.token_url)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
      http.post(uri.request_uri, URI.encode_www_form(params.merge(client_id: sign_in.client_id)), "Content-Type" => "application/x-www-form-urlencoded")
    end
    body = JSON.parse(response.body.to_s)
    raise Failed, "The provider did not accept the sign in." unless response.is_a?(Net::HTTPSuccess) && body["access_token"].present?

    body
  rescue JSON::ParserError, SocketError, Timeout::Error, SystemCallError, OpenSSL::SSL::SSLError
    raise Failed, "The provider could not be reached to sign in."
  end

  def expires_at(tokens) = tokens["expires_in"].present? ? tokens["expires_in"].to_i.seconds.from_now : nil

  # The address the provider says the tokens are for, read from the ID token without trusting it for anything else.
  def email(tokens)
    payload = tokens["id_token"].to_s.split(".")[1]
    payload && JSON.parse(Base64.urlsafe_decode64(payload + ("=" * (-payload.length % 4))))["email"]
  rescue JSON::ParserError, ArgumentError
    nil
  end
end
