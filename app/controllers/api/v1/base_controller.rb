class Api::V1::BaseController < ActionController::API
  # Verify Slack signature on all requests by default
  # Controllers can skip with: skip_before_action :verify_slack_signature!
  before_action :verify_slack_signature!

  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from ActionController::ParameterMissing, with: :bad_request
  rescue_from Slack::SignatureVerifier::InvalidSignatureError,
              Slack::SignatureVerifier::ReplayAttackError, with: :unauthorized

  private

  def verify_slack_signature!
    Slack::SignatureVerifier.verify!(request)
  end

  def not_found(exception)
    render json: { error: "Not found" }, status: :not_found
  end

  def bad_request(exception)
    render json: { error: "Bad request" }, status: :bad_request
  end

  def unauthorized(exception)
    render json: { error: "Unauthorized" }, status: :unauthorized
  end

  def server_error(exception)
    render json: { error: "Internal server error" }, status: :internal_server_error
  end
end
