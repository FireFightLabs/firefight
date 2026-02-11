# Routes interactions to appropriate handlers based on type and callback/action ID
# Platform-agnostic — works with any Interaction object
class InteractionDispatcher
  VIEW_SUBMISSION_HANDLERS = {
    Identifiers::SHARE_INCIDENTS_CHANNEL_MODAL => Interactions::ShareModalSubmissionHandler,
    Identifiers::INCIDENT_CREATION_MODAL => Interactions::IncidentCreationHandler
  }.freeze

  BLOCK_ACTION_HANDLERS = {
    Identifiers::PREVIEW_ANNOUNCEMENT => Interactions::PreviewAnnouncementHandler,
    Identifiers::SHARE_INCIDENTS_CHANNEL => Interactions::ShareChannelHandler,
    Identifiers::PREVIEW_HOMEPAGE_DISABLED => Interactions::NoopHandler,
    Identifiers::PREVIEW_SUBSCRIBE_DISABLED => Interactions::NoopHandler,
    Identifiers::HOME_ACTION_SELECT => Interactions::HomeActionSelectHandler
  }.freeze

  SHORTCUT_HANDLERS = {
    Identifiers::CREATE_INCIDENT_SHORTCUT => Interactions::CreateIncidentShortcutHandler
  }.freeze

  def self.dispatch(interaction)
    handler = find(interaction)
    handler.execute(interaction)
  end

  def self.find(interaction)
    case interaction.type
    when Interaction::VIEW_SUBMISSION
      VIEW_SUBMISSION_HANDLERS[interaction.callback_id] || Interactions::UnknownHandler
    when Interaction::BLOCK_ACTIONS
      BLOCK_ACTION_HANDLERS[interaction.action_id] || Interactions::UnknownHandler
    when Interaction::SHORTCUT
      SHORTCUT_HANDLERS[interaction.callback_id] || Interactions::UnknownHandler
    when Interaction::VIEW_CLOSED
      Interactions::ViewClosedHandler
    else
      Interactions::UnknownHandler
    end
  end
end
