class Api::V1::InteractionsController < Api::V1::BaseController
  # POST /api/v1/interactions
  # Handles Slack interactive components (modal submissions, button clicks, etc.)
  #
  # Signature verification handled by BaseController before_action
  def create
    # Parse the payload (Slack sends it as a form-encoded 'payload' parameter)
    payload = parse_payload
    return unless payload # parse_payload renders error and returns nil on failure

    # Log the interaction for now
    Rails.logger.info("Slack interaction received: #{payload["type"]}")
    Rails.logger.info("Payload: #{payload.inspect}")

    # Handle different interaction types
    case payload["type"]
    when "view_submission"
      handle_view_submission(payload)
    when "block_actions"
      handle_block_actions(payload)
    when "view_closed"
      handle_view_closed(payload)
    else
      Rails.logger.warn("Unknown interaction type: #{payload["type"]}")
    end

    # Acknowledge receipt
    head :ok
  end

  private

  def parse_payload
    payload_json = params[:payload]
    JSON.parse(payload_json)
  rescue JSON::ParserError => e
    Rails.logger.error("Failed to parse Slack payload: #{e.message}")
    render json: { error: "Invalid payload" }, status: :bad_request
    nil
  end

  # Handle modal submission (when user clicks "Submit" on modal)
  def handle_view_submission(payload)
    Rails.logger.info("Modal submitted")
    Rails.logger.info("Callback ID: #{payload.dig("view", "callback_id")}")
    Rails.logger.info("Values: #{payload.dig("view", "state", "values").inspect}")

    # TODO: Implement incident creation logic here
    # For now, just log the submission

    # Return empty response to close the modal
    # Or return errors to keep modal open:
    # render json: {
    #   response_action: "errors",
    #   errors: {
    #     "block_id": "error message"
    #   }
    # }
  end

  # Handle button clicks and other block actions
  def handle_block_actions(payload)
    action = payload.dig("actions", 0)
    action_id = action&.dig("action_id")

    service = SlackInteractionsService.new

    case action_id
    when "preview_announcement"
      result = service.handle_preview_announcement(payload)
      render json: result
    when "preview_homepage_disabled", "preview_subscribe_disabled"
      # These are disabled preview buttons - do nothing
      render json: { response_action: "clear" }
    else
      Rails.logger.info("Block action triggered")
      Rails.logger.info("Actions: #{payload["actions"].inspect}")
      # TODO: Implement other button click handlers
    end
  end

  # Handle modal close (when user clicks "Cancel" or X)
  def handle_view_closed(payload)
    Rails.logger.info("Modal closed without submission")
  end
end
