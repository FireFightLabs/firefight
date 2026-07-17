# The MCP entry point: stateless Streamable HTTP (every POST self-contained,
# no sessions, no SSE) so it runs under multi-worker Puma. Auth is the same
# Bearer ApiKey as the REST API — either token kind resolves to a principal.
class McpController < ActionController::API
  SERVER_NAME = "firefight".freeze
  SERVER_VERSION = "1.0.0".freeze
  INSTRUCTIONS = "Read-only access to a Firefight incident-management workspace: incidents, " \
                 "alerts, the service catalog, and alert-routing dry runs. All data is scoped " \
                 "to the token's workspace.".freeze

  rate_limit to: 1000, within: 1.minute, by: -> { Current.api_key&.id }, with: :rate_limit_exceeded

  before_action :authenticate!, only: :create

  def create
    response_json = mcp_server.handle_json(request.raw_post)
    return head :accepted if response_json.nil?

    render json: response_json
  end

  def method_not_allowed
    head :method_not_allowed
  end

  private

  def authenticate!
    token = request.headers["Authorization"]&.match(/\ABearer (.+)\z/)&.captures&.first
    api_key = ApiKey.authenticate(token)
    unless api_key
      response.set_header("WWW-Authenticate", "Bearer realm=\"Firefight MCP\"")
      return render json: { error: "unauthorized", message: "Provide a Firefight API token as 'Authorization: Bearer ff_...'" }, status: :unauthorized
    end

    Current.workspace = api_key.workspace
    Current.api_key = api_key
    Current.principal = api_key.principal
    api_key.touch_last_used!
    annotate_trace
  end

  def mcp_server
    MCP::Server.new(
      name: SERVER_NAME,
      version: SERVER_VERSION,
      instructions: INSTRUCTIONS,
      tools: Mcp::Tools.all,
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
