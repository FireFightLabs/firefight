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
    OpenTelemetry::Trace.current_span.add_attributes({ "firefight.source" => "slack" })
    Firefight::TRACER.in_span("slack.verify_signature") do
      Slack::SignatureVerifier.verify!(request)
    end
  end

  # Provision a workspace membership if one doesn't exist yet.
  # Centralized here so commands and interactions share the same path —
  # downstream handlers can trust find_by!(platform_user_id:) for the actor.
  # Best-effort: provisioning failure logs a warning, dispatch continues.
  def ensure_membership!(workspace:, platform_user_id:)
    Firefight::TRACER.in_span("slack.ensure_membership") do
      return unless workspace && platform_user_id

      WorkspaceMemberProvisioner.find_or_provision!(
        workspace: workspace,
        platform_user_id: platform_user_id,
        adapter: workspace.adapter
      )
    rescue StandardError => e
      Rails.logger.warn({
        event: "membership.provisioning_failed",
        platform_user_id: platform_user_id,
        error: e.message
      })
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
    render json: { error: "Internal server error" }, status: :internal_server_error
  end
end
