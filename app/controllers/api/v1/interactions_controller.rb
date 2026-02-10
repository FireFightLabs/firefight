class Api::V1::InteractionsController < Api::V1::BaseController
  # POST /api/v1/interactions
  # Handles Slack interactive components (modal submissions, button clicks, etc.)
  #
  # Signature verification handled by BaseController before_action
  def create
    payload = parse_payload
    return unless payload

    result = InteractionDispatcher.dispatch(payload)

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
    Rails.logger.error("Failed to parse Slack payload: #{e.message}")
    render json: { error: "Invalid payload" }, status: :bad_request
    nil
  end
end
