# Where a command in Halon's terminal reaches the workspace's connected tools: ff, and a provider's own command line tool
# pointed here instead of the provider. The box holds only its command's token, and every call is made by the relay as
# the run that started the command (Chat::Terminal::Relay).
class SandboxRelayController < ActionController::API
  rate_limit to: 600, within: 1.minute, by: -> { Chat::TerminalSession.digest(token) }, with: -> { head :too_many_requests }

  before_action :authenticate

  def index
    render json: { tools: relay.tools(params[:q]) }
  end

  def show
    described = relay.describe(params[:name])
    return render(json: { error: "No tool called #{params[:name]} can be called here." }, status: :not_found) unless described

    render json: described
  end

  def create
    said = relay.call(params[:name], arguments)
    render json: { outcome: said.outcome, text: said.text }
  end

  def clis
    render json: { clis: relay.clis(token).map(&:to_h) }
  end

  def api
    answered = relay.api(params[:connection], request.method, params[:path].to_s, request.query_parameters, body)
    render json: answered.body, status: answered.status
  end

  private

  def authenticate
    @session = Chat::TerminalSession.authenticate(token)
    render json: { error: Chat::TerminalSession::ENDED }, status: :unauthorized unless @session
  end

  def relay = @relay ||= Chat::Terminal::Relay.new(@session)

  def arguments
    parsed = body
    parsed.is_a?(Hash) ? parsed["arguments"].to_h : {}
  end

  def body
    request.raw_post.present? ? JSON.parse(request.raw_post) : nil
  rescue JSON::ParserError
    nil
  end

  # A call carries a customer's data both ways, so none of it reaches the request log.
  def process_action(*)
    request.env["action_dispatch.parameter_filter"] = [ /./ ]
    super
  end

  def token = request.authorization.to_s.delete_prefix("Bearer ").presence
end
