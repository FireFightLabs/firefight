# Where git in the sandbox fetches and pushes, as smart HTTP. The box signs in with its code change session's token as
# the password, and Integrations::GitGate decides what passes and streams it to the code host.
class CodeAgentGitController < ActionController::API
  include ActionController::Live

  rate_limit to: 120, within: 1.minute, by: -> { CodeAgentSession.digest(password.to_s) }, with: -> { head :too_many_requests }

  def info_refs
    through_gate { |gate| gate.advertise(params[:service].to_s, headers: request.headers) { |*event| relay(*event) } }
  end

  def upload_pack
    through_gate(Integrations::GitGate::MAX_UPLOAD_BYTES) do |gate, body|
      gate.upload(body, length: request.content_length, headers: request.headers) { |*event| relay(*event) }
    end
  end

  def receive_pack
    through_gate(Integrations::GitGate::MAX_PUSH_BYTES) do |gate, body|
      gate.receive(body, length: request.content_length, headers: request.headers) { |*event| relay(*event) }
    end
  end

  private

  def through_gate(limit = nil)
    session = CodeAgentSession.authenticate(password)
    return unauthorized unless session
    return head(:content_too_large) if limit && request.content_length.to_i > limit

    yield Integrations::GitGate.new(session), (Limited.new(request.body, limit) if limit)
  rescue Integrations::GitGate::Refused, Limited::TooLarge => error
    Rails.logger.warn({ event: "code_agent.git_refused", reason: error.message }.to_json)
    render plain: "#{error.message}\n", status: :forbidden unless response.committed?
  rescue Integrations::Error => error
    Rails.logger.warn({ event: "code_agent.git_unreachable", error: error.message.truncate(200) }.to_json)
    render plain: "The code host could not be reached.\n", status: :bad_gateway unless response.committed?
  ensure
    response.stream.close
  end

  def relay(event, *rest)
    if event == :start
      status, passed = rest
      response.status = status
      passed.each { |name, value| response.headers[name] = value }
    else
      response.stream.write(rest.first)
    end
  end

  # git asks again with its credentials when told who to sign in as.
  def unauthorized
    response.headers["WWW-Authenticate"] = 'Basic realm="Firefight"'
    head :unauthorized
  end

  def password
    return unless ActionController::HttpAuthentication::Basic.has_basic_credentials?(request)

    ActionController::HttpAuthentication::Basic.user_name_and_password(request).last.presence
  end

  # A request carries a customer's source code, so none of it reaches the request log.
  def process_action(*)
    request.env["action_dispatch.parameter_filter"] = [ /./ ]
    super
  end

  # A request body read in pieces that stops past its limit, for a push sent without a length.
  class Limited
    class TooLarge < StandardError; end

    def initialize(io, limit)
      @io = io
      @limit = limit
      @read = 0
    end

    def read(length = nil, buffer = nil)
      data = @io.read(length, *buffer)
      @read += data.to_s.bytesize
      raise TooLarge, "The request is larger than #{@limit / 1.megabyte} MB." if @read > @limit

      data
    end
  end
end
