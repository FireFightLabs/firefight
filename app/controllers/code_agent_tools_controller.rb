# The tools a coding agent in the sandbox reaches besides its model, as an MCP server on its session's token. They search
# and read the public web for a library's documentation, so the box itself never reaches the web for the agent.
class CodeAgentToolsController < ActionController::API
  SERVER_NAME = "firefight-code-agent".freeze
  SERVER_VERSION = "1.0.0".freeze

  rate_limit to: 60, within: 1.minute, by: -> { CodeAgentSession.digest(token) }, with: -> { head :too_many_requests }

  def create
    session = CodeAgentSession.authenticate(token)
    return render(json: { error: CodeAgentSession::ENDED }, status: :unauthorized) unless session

    answer = MCP::Server.new(name: SERVER_NAME, version: SERVER_VERSION, tools: CodeAgent::WebTools.for(session)).handle_json(request.raw_post)
    answer.nil? ? head(:accepted) : render(json: answer)
  end

  def method_not_allowed
    head :method_not_allowed
  end

  private

  # A request can carry a customer's code in a search, so none of it reaches the request log.
  def process_action(*)
    request.env["action_dispatch.parameter_filter"] = [ /./ ]
    super
  end

  def token = request.authorization.to_s.delete_prefix("Bearer ").presence
end
