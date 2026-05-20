class Api::V1::CommandsController < Api::V1::BaseController
  def create
    command = Slack::CommandAdapter.parse(command_params.to_h)

    unless command.valid?
      Rails.logger.error({ event: "command.unknown_workspace", errors: command.errors.full_messages })
      return render_response(Command.ephemeral(unknown_workspace_message))
    end

    ensure_membership!(workspace: command.workspace, platform_user_id: command.user_id)
    result = CommandDispatcher.dispatch(command)
    render_response(result)
  rescue StandardError => e
    OpenTelemetry::Trace.current_span.record_exception(e)
    Rails.logger.error({
      event: "command.failed",
      error_class: e.class.name,
      workspace_id: command&.workspace&.id,
      error: e.message,
      backtrace: e.backtrace&.first(5)
    })
    render_response(Command.ephemeral("Sorry, something went wrong. Please try again."))
  end

  private

  def render_response(result)
    if result.is_a?(Hash) && result[:response_type] == Command::EPHEMERAL
      render json: result
    else
      head :ok
    end
  end

  # APP_HOST falls back to the request host so the install link is always
  # generated even if the env var is missing — the outer rescue would
  # otherwise swallow ENV.fetch's KeyError and the user would see the
  # generic "something went wrong" message instead of the install link.
  def unknown_workspace_message
    host = ENV["APP_HOST"].presence || request.host
    install_url = "https://#{host}/onboarding/install"
    "Firefight isn't connected to this Slack workspace. " \
      "A workspace admin can <#{install_url}|reinstall the app> to fix this."
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
