class Api::V1::CommandsController < Api::V1::BaseController
  # POST /api/v1/commands
  # Handles Slack slash commands (/firefight, /ff)
  #
  # Signature verification handled by BaseController before_action
  def create
    # Find workspace by Slack team_id
    # Raises ParameterMissing if team_id not present (handled by BaseController)
    # Raises RecordNotFound if workspace not found (handled by BaseController)
    find_workspace!

    # Enqueue background job to process command
    # Job must complete within 3 seconds for modal operations (trigger_id expiration)
    ProcessCommandJob.perform_later(Platforms::SLACK, command_params.to_h)

    # Respond immediately to Slack (must respond within 3 seconds)
    # Empty 200 OK response is all Slack needs
    head :ok
  end

  private

  def find_workspace!
    team_id = params.require(:team_id)
    Workspace.find_by!(platform: Platforms::SLACK, platform_id: team_id)
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
