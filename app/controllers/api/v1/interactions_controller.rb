class Api::V1::InteractionsController < Api::V1::BaseController
  def create
    payload = parse_payload
    return unless payload

    interaction = Slack::InteractionParser.parse(payload)
    workspace = interaction.workspace

    # An unknown or suspended workspace. This payload shape leaves no way to answer, so it is dropped.
    if workspace.nil?
      Rails.logger.info({ event: "interaction.unknown_workspace", team_id: interaction.team_id })
      return head :ok
    end
    if workspace.suspended?
      Rails.logger.info({ event: "interaction.suspended_workspace", workspace_id: workspace.id })
      return head :ok
    end

    # Who is acting is resolved once, by the dispatcher.
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
