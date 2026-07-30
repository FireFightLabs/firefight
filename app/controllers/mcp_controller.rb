# The MCP entry point: stateless Streamable HTTP (every POST self-contained,
# no sessions, no SSE) so it runs under multi-worker Puma. Auth is the same
# Bearer ApiKey as the REST API — either token kind resolves to a principal.
class McpController < ActionController::API
  SERVER_NAME = "firefight".freeze
  SERVER_VERSION = "1.0.0".freeze
  INSTRUCTIONS = "Read-only access to a Firefight incident-management workspace: incidents, " \
                 "alerts, the service catalog, and alert-routing dry runs. All data is scoped " \
                 "to the token's workspace. Product docs: #{Mcp::Docs::BASE} — every page is " \
                 "fetchable as raw markdown; index at #{Mcp::Docs::INDEX}.".freeze

  before_action :authenticate!, only: :create
  before_action :block_suspended_workspace, only: :create
  # Declared after authenticate! so the per-principal bucket is populated.
  rate_limit to: 1000, within: 1.minute, by: -> { Current.principal&.id }, with: :rate_limit_exceeded

  def create
    response_json = mcp_server.handle_json(request.raw_post)
    return head :accepted if response_json.nil?

    render json: response_json
  end

  def method_not_allowed
    head :method_not_allowed
  end

  private

  # Two credential kinds resolve to one principal model: ff_-prefixed API
  # tokens (either mode) and OAuth access tokens minted by the consent flow
  # (resource owner = the consenting membership).
  def authenticate!
    token = request.headers["Authorization"]&.match(/\ABearer (.+)\z/)&.captures&.first
    return unauthorized! if token.blank?

    if token.start_with?(ApiKey::TOKEN_PREFIX)
      authenticate_api_key!(token)
    else
      authenticate_oauth_token!(token)
    end
  end

  def authenticate_api_key!(token)
    api_key = ApiKey.authenticate(token)
    return unauthorized! unless api_key

    Current.workspace = api_key.workspace
    Current.api_key = api_key
    Current.principal = api_key.principal
    api_key.touch_last_used!
    annotate_trace
  end

  def authenticate_oauth_token!(token)
    access_token = Doorkeeper::AccessToken.by_token(token)
    return unauthorized! unless access_token&.acceptable?(Doorkeeper.config.default_scopes.to_a)

    membership = WorkspaceMembership.find_by(id: access_token.resource_owner_id)
    return unauthorized! unless membership

    Current.workspace = membership.workspace
    Current.principal = membership
    annotate_trace
  end

  def block_suspended_workspace
    return unless Current.workspace&.suspended?

    render json: {
      error: "workspace_suspended",
      message: Current.workspace.suspension_message
    }, status: :forbidden
  end

  def unauthorized!
    response.set_header(
      "WWW-Authenticate",
      "Bearer realm=\"Firefight MCP\", resource_metadata=\"#{request.base_url}/.well-known/oauth-protected-resource\""
    )
    render json: {
      error: "unauthorized",
      message: "Authenticate with a Firefight API token ('Authorization: Bearer ff_...') or connect via OAuth."
    }, status: :unauthorized
  end

  def mcp_server
    MCP::Server.new(
      name: SERVER_NAME,
      version: SERVER_VERSION,
      instructions: INSTRUCTIONS,
      tools: Mcp::Tools.all + Mcp::ConnectionToolFactory.tools_for(Current.workspace),
      server_context: {
        workspace: Current.workspace,
        principal: Current.principal,
        api_key: Current.api_key
      }
    )
  end

  def annotate_trace
    OpenTelemetry::Trace.current_span.add_attributes({
      "firefight.source" => "mcp",
      "firefight.workspace.id" => Current.workspace&.id,
      "firefight.principal" => Current.principal&.principal_label
    }.compact)
  end

  def rate_limit_exceeded
    render json: { error: "rate_limit_exceeded", message: "Rate limit exceeded. Try again later." }, status: :too_many_requests
  end
end
