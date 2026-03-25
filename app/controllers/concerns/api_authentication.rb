module ApiAuthentication
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_api_key!
  end

  private

  def authenticate_api_key!
    token = extract_bearer_token
    return render_unauthorized("Missing authorization header") unless token

    api_key = ApiKey.authenticate(token)
    return render_unauthorized("Invalid or expired API key") unless api_key

    Current.workspace = api_key.workspace
    Current.api_key = api_key
    api_key.touch_last_used!
  end

  def authorize!(resource, action)
    unless Current.api_key.has_permission?(resource, action)
      raise ForbiddenError, "API key lacks '#{action}' permission on '#{resource}'"
    end
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
