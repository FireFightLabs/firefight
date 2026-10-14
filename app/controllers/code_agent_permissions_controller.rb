# Where the box puts a coding agent's permission question, on its session's token: OpenCode asks before a step
# Fixing::PERMISSIONS marks ask, and Halon or the person decides it (CodeAgentPermissionService). One request waits a
# little for the decision and otherwise says to ask again.
class CodeAgentPermissionsController < ActionController::API
  rate_limit to: 60, within: 1.minute, by: -> { CodeAgentSession.digest(token) }, with: -> { head :too_many_requests }

  def create
    session = CodeAgentSession.authenticate(token)
    return render(json: { error: CodeAgentSession::ENDED }, status: :unauthorized) unless session

    asked = params.permit(:id, :permission, :sessionID, :answeredInBox, patterns: [], events: []).to_h
    metadata = params[:metadata].respond_to?(:to_unsafe_h) ? params[:metadata].to_unsafe_h : {}
    return render(json: { error: "Name the request and the permission." }, status: :unprocessable_content) if asked["id"].blank? || asked["permission"].blank?

    permission, reply = CodeAgentPermissionService.ask!(session, request_id: asked["id"], permission: asked["permission"], patterns: asked["patterns"],
                                                                 metadata: metadata, events: asked["events"], agent_session: asked["sessionID"],
                                                                 answered_in_box: ActiveModel::Type::Boolean.new.cast(asked["answeredInBox"]), hidden: [ token ])
    render json: { "permission" => permission.id, **(reply || { "wait" => true }) }
  end

  private

  # What the agent asks about can quote a customer's code, so none of it reaches the request log.
  def process_action(*)
    request.env["action_dispatch.parameter_filter"] = [ /./ ]
    super
  end

  def token = request.authorization.to_s.delete_prefix("Bearer ").presence
end
