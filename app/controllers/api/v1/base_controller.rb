class Api::V1::BaseController < ActionController::API
  # ActionController::API doesn't include CSRF protection by default
  # These endpoints use Slack signature verification instead

  # Error handling
  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from ActionController::ParameterMissing, with: :bad_request

  private

  def not_found(exception)
    render json: { error: exception.message }, status: :not_found
  end

  def bad_request(exception)
    render json: { error: exception.message }, status: :bad_request
  end

  def server_error(exception)
    render json: { error: "Internal server error" }, status: :internal_server_error
  end
end
