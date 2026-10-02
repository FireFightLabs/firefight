# Where a coding agent in the sandbox reaches its model. The box holds only its session's token, sent the way the
# agent's provider sends a key, and the answer streams back as the provider gives it.
class CodeAgentController < ActionController::API
  include ActionController::Live

  rate_limit to: 120, within: 1.minute, by: -> { CodeAgentSession.digest(token) }, with: -> { head :too_many_requests }

  def forward
    session = CodeAgentSession.authenticate(token)
    return render(json: { error: { message: CodeAgentSession::ENDED } }, status: :unauthorized) unless session

    passed = FirefightAi::ModelProxy.passed_headers(session.provider).index_with { |name| request.headers[name] }
    CodeAgent::Relay.new(session).forward(path: params[:path].to_s, body: request.raw_post, headers: passed) do |event, *rest|
      if event == :start
        response.status, response.headers["Content-Type"] = rest
      else
        response.stream.write(rest.first)
      end
    end
  rescue FirefightAi::ModelProxy::Refused => error
    render json: { error: { message: error.message } }, status: :forbidden unless response.committed?
  ensure
    response.stream.close
  end

  private

  # A request carries a customer's source code to the model, so none of it reaches the request log.
  def process_action(*)
    request.env["action_dispatch.parameter_filter"] = [ /./ ]
    super
  end

  def token = request.headers["x-api-key"].presence || request.authorization.to_s.delete_prefix("Bearer ").presence
end
