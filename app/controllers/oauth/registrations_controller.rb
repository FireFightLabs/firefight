# RFC 7591 dynamic client registration: MCP clients self-register as public
# clients (no secret; PKCE enforced at authorization time). Open by design,
# so it is rate limited and stores nothing sensitive.
class Oauth::RegistrationsController < ActionController::API
  MAX_REDIRECT_URIS = 5

  rate_limit to: 10, within: 1.minute, by: -> { request.remote_ip }, with: :rate_limit_exceeded

  def create
    redirect_uris = Array(params[:redirect_uris]).first(MAX_REDIRECT_URIS).map(&:to_s)
    application = Doorkeeper::Application.new(
      name: params[:client_name].presence || "MCP client",
      redirect_uri: redirect_uris.join("\n"),
      confidential: false,
      scopes: Doorkeeper.config.default_scopes.to_a.join(" ")
    )

    if application.save
      render json: {
        client_id: application.uid,
        client_name: application.name,
        redirect_uris: redirect_uris,
        token_endpoint_auth_method: "none",
        grant_types: [ "authorization_code", "refresh_token" ],
        response_types: [ "code" ]
      }, status: :created
    else
      render json: {
        error: "invalid_client_metadata",
        error_description: application.errors.full_messages.join("; ")
      }, status: :bad_request
    end
  end

  private

  def rate_limit_exceeded
    render json: { error: "rate_limited", error_description: "Too many registrations; try again later." }, status: :too_many_requests
  end
end
