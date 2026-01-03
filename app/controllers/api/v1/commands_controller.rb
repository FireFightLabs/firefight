class Api::V1::CommandsController < Api::V1::BaseController
  # POST /api/v1/commands
  # Handles Slack slash commands (/firefight, /ff)
  def create
    # Verify Slack signature
    verify_slack_signature!

    # Find workspace by Slack team_id
    workspace = find_workspace!

    # Enqueue background job to process command
    # Must complete within 3 seconds due to trigger_id expiration
    ProcessCommandJob.perform_later("slack", command_params.to_h)

    # Respond immediately to Slack (must respond within 3 seconds)
    render json: { ok: true }, status: :ok
  end

  private

  def verify_slack_signature!
    Slack::SignatureVerifier.verify!(request)
  rescue Slack::SignatureVerifier::InvalidSignatureError, Slack::SignatureVerifier::ReplayAttackError => e
    render json: { error: "Unauthorized: #{e.message}" }, status: :unauthorized
  end

  def find_workspace!
    workspace = Workspace.find_by!(platform: "slack", platform_id: params[:team_id])
    workspace
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Workspace not found. Please install the Firefight app first." }, status: :not_found
    nil
  end

  def command_params
    params.permit(
      :token,
      :team_id,
      :team_domain,
      :channel_id,
      :channel_name,
      :user_id,
      :user_name,
      :command,
      :text,
      :response_url,
      :trigger_id,
      :api_app_id
    )
  end
end
