# Routes Slack interactions to appropriate handlers based on payload type and callback/action ID
# Mirrors CommandDispatcher but synchronous — interactions need response bodies for modal control
class InteractionDispatcher
  # view_submission handlers keyed by callback_id
  VIEW_SUBMISSION_HANDLERS = {
    Slack::Identifiers::SHARE_INCIDENTS_CHANNEL_MODAL => Interactions::ShareModalSubmissionHandler,
    Slack::Identifiers::INCIDENT_CREATION_MODAL => Interactions::IncidentCreationHandler
  }.freeze

  # block_actions handlers keyed by action_id
  BLOCK_ACTION_HANDLERS = {
    Slack::Identifiers::PREVIEW_ANNOUNCEMENT => Interactions::PreviewAnnouncementHandler,
    Slack::Identifiers::SHARE_INCIDENTS_CHANNEL => Interactions::ShareChannelHandler,
    Slack::Identifiers::PREVIEW_HOMEPAGE_DISABLED => Interactions::NoopHandler,
    Slack::Identifiers::PREVIEW_SUBSCRIBE_DISABLED => Interactions::NoopHandler,
    Slack::Identifiers::HOME_ACTION_SELECT => Interactions::HomeActionSelectHandler
  }.freeze

  # shortcut handlers keyed by callback_id
  SHORTCUT_HANDLERS = {
    Slack::Identifiers::CREATE_INCIDENT_SHORTCUT => Interactions::CreateIncidentShortcutHandler
  }.freeze

  # Find and execute the appropriate handler
  #
  # @param payload [Hash] Parsed Slack interaction payload
  # @return [Hash, nil] Response hash for controller, or nil for head :ok
  def self.dispatch(payload)
    handler = find(payload)
    handler.execute(payload)
  end

  # Find the appropriate handler for a payload
  #
  # @param payload [Hash] Parsed Slack interaction payload
  # @return [Class] Handler class
  def self.find(payload)
    case payload["type"]
    when "view_submission"
      callback_id = payload.dig("view", "callback_id")
      VIEW_SUBMISSION_HANDLERS[callback_id] || Interactions::UnknownHandler
    when "block_actions"
      action_id = payload.dig("actions", 0, "action_id")
      BLOCK_ACTION_HANDLERS[action_id] || Interactions::UnknownHandler
    when "shortcut"
      callback_id = payload["callback_id"]
      SHORTCUT_HANDLERS[callback_id] || Interactions::UnknownHandler
    when "view_closed"
      Interactions::ViewClosedHandler
    else
      Interactions::UnknownHandler
    end
  end
end
