class Api::V1::InteractionsController < Api::V1::BaseController
  # POST /api/v1/interactions
  # Handles Slack interactive components (modal submissions, button clicks, etc.)
  #
  # Signature verification handled by BaseController before_action
  def create
    payload = parse_payload
    return unless payload

    interaction = Slack::InteractionParser.parse(payload)
    workspace = interaction.workspace

    # A click from a workspace Firefight no longer knows, or one that is
    # suspended. Commands and modals are refused with a message elsewhere,
    # and this payload shape leaves no way to answer, so it is dropped.
    if workspace.nil?
      Rails.logger.info({ event: "interaction.unknown_workspace", team_id: interaction.team_id })
      return head :ok
    end
    if workspace.suspended?
      Rails.logger.info({ event: "interaction.suspended_workspace", workspace_id: workspace.id })
      return head :ok
    end

    # Who is acting is resolved once, by the interaction's own principal, on
    # the way through the dispatcher.
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
