class Api::V1::CommandsController < Api::V1::BaseController
  # POST /api/v1/commands
  # Handles Slack slash commands (/firefight, /ff)
  def create
    command = Slack::CommandAdapter.parse(command_params.to_h.with_indifferent_changes)


  unless command.valid?
    Rails.logger.error({ event: "command.unknown_workspace", errors: command.errors.full_messages })
    install_url = "https://#{ENV.fetch('APP_HOST')}/onboarding/install"
    return render json: {
      response_type: "ephemeral",
      text: "Firefight isn't connected to this Slack workspace. " \
            "A workspace admin can <#{install_url}|reinstall the app> to fix this."
    }
  end

    ensure_member_provisioned(command)
    result = CommandDispatcher.dispatch(command)
    render_response(result)
  rescue StandardError => e
    Rails.logger.error({ event: "command.failed", workspace_id: command&.workspace&.id, error: e.message, backtrace: e.backtrace&.first(5) })
    render json: { response_type: "ephemeral", text: "Sorry, something went wrong. Please try again." }
  end

  private

  def render_response(result)
    if result.is_a?(Hash) && result[:response_type] == Command::EPHEMERAL
      render json: { response_type: "ephemeral", text: result[:text], blocks: result[:blocks] }.compact
    else
      head :ok
    end
  end

  def ensure_member_provisioned(command)
    workspace = command.workspace
    return unless workspace

    WorkspaceMemberProvisioner.find_or_provision!(
      workspace: workspace,
      platform_user_id: command.user_id,
      adapter: workspace.adapter
    )
  rescue StandardError => e
    Rails.logger.warn({
      event: "command.provisioning_failed",
      user_id: command.user_id,
      error: e.message
    })
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
