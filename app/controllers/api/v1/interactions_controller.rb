class Api::V1::InteractionsController < Api::V1::BaseController
  # POST /api/v1/interactions
  # Handles Slack interactive components (modal submissions, button clicks, etc.)
  #
  # Signature verification handled by BaseController before_action
  def create
    payload = parse_payload
    return unless payload

    interaction = Slack::InteractionParser.parse(payload)
    workspace = Workspace.find_by(platform: Platforms::SLACK, platform_id: interaction.team_id)

    # Commands and modals are already refused with a message, so what lands
    # here is a click on an old message. Dropping it is the only option this
    # payload shape leaves.
    if workspace&.suspended?
      Rails.logger.info({ event: "interaction.suspended_workspace", workspace_id: workspace.id })
      return head :ok
    end

    ensure_membership!(workspace: workspace, platform_user_id: interaction.user_id)
    result = InteractionDispatcher.dispatch(interaction)

    if result
      render json: result
    else
      head :ok
    end
  end

  private

  def parse_payload
    payload_json = params[:payload]

    unless payload_json.is_a?(String)
      render json: { error: "Invalid payload" }, status: :bad_request
      return
    end

    JSON.parse(payload_json)
  rescue JSON::ParserError => e
    Rails.logger.error({ event: "interactions_controller.failed_to_parse_payload", error: e.message })
    render json: { error: "Invalid payload" }, status: :bad_request
    nil
  end
end
