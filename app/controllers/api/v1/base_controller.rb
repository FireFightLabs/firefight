class Api::V1::BaseController < ActionController::API
  # Verify Slack signature on all requests by default
  # Controllers can skip with: skip_before_action :verify_slack_signature!
  before_action :verify_slack_signature!

  # Registered first so the more specific handlers below take precedence
  # (Rails matches rescue_from handlers last-defined-first).
  rescue_from StandardError, with: :server_error
  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from ActionController::ParameterMissing, with: :bad_request
  rescue_from Slack::SignatureVerifier::InvalidSignatureError,
              Slack::SignatureVerifier::ReplayAttackError, with: :unauthorized

  private

  def verify_slack_signature!
    OpenTelemetry::Trace.current_span.add_attributes({ "firefight.source" => "slack" })
    Firefight::TRACER.in_span("slack.verify_signature") do
      Slack::SignatureVerifier.verify!(request)
    end
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
    Rails.logger.error({
      event: "api.unhandled_exception",
      path: request.path,
      error_class: exception.class.name,
      error: exception.message,
      backtrace: exception.backtrace&.first(20)
    })

    span = OpenTelemetry::Trace.current_span
    span.record_exception(exception)
    span.status = OpenTelemetry::Trace::Status.error(exception.message)

    render json: { error: "Internal server error" }, status: :internal_server_error
  end
end
