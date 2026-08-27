module ApiAuthentication
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_api_key!
    around_action :finalize_ability_authorization
  end

  private

  def authenticate_api_key!
    token = extract_bearer_token
    return render_unauthorized("Missing authorization header") unless token

    api_key = ApiKey.authenticate(token)
    return render_unauthorized("Invalid or expired API key") unless api_key

    Current.workspace = api_key.workspace
    Current.api_key = api_key
    Current.principal = api_key.principal
    api_key.touch_last_used!
  end

  # Personal tokens resolve to the human principal (member-level reads),
  # service keys to themselves (their grants). Write-risk actions get a
  # write-ahead ledger row, finalized by the around_action once the
  # controller action completes.
  def authorize!(resource, action)
    @ability_authorization = AbilityGateway.authorize!(
      principal: Current.principal,
      action_key: Ability::Action.system_key(resource, action),
      workspace: Current.workspace,
      params: request_binding_params,
      context: { source: AbilityGateway::SOURCE_API, approval_id: request.headers["X-Approval-Id"] }
    )
  rescue AbilityGateway::Denied
    raise ForbiddenError, "API key lacks '#{action}' permission on '#{resource}'"
  end

  # Binds an approval to the exact request body without putting the body
  # (potential PII) into the ledger. An approved retry must be byte-identical.
  def request_binding_params
    return {} if request.raw_post.blank?

    { "body_digest" => Digest::SHA256.hexdigest(request.raw_post) }
  end

  def finalize_ability_authorization
    yield
    @ability_authorization&.finalize_success!
  rescue => error
    @ability_authorization&.finalize_error!(error)
    raise
  end

  class ForbiddenError < StandardError; end

  def current_workspace
    Current.workspace
  end

  def extract_bearer_token
    request.headers["Authorization"]&.match(/\ABearer (.+)\z/)&.captures&.first
  end

  def render_unauthorized(message)
    render json: error_response("unauthorized", message), status: :unauthorized
  end
end
