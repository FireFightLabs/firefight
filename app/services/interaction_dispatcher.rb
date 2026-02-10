# Routes interactions to appropriate handlers based on type and callback/action ID
# Normalizes raw payload into an Interaction object before dispatching
class InteractionDispatcher
  VIEW_SUBMISSION_HANDLERS = {
    Slack::Identifiers::SHARE_INCIDENTS_CHANNEL_MODAL => Interactions::ShareModalSubmissionHandler,
    Slack::Identifiers::INCIDENT_CREATION_MODAL => Interactions::IncidentCreationHandler
  }.freeze

  BLOCK_ACTION_HANDLERS = {
    Slack::Identifiers::PREVIEW_ANNOUNCEMENT => Interactions::PreviewAnnouncementHandler,
    Slack::Identifiers::SHARE_INCIDENTS_CHANNEL => Interactions::ShareChannelHandler,
    Slack::Identifiers::PREVIEW_HOMEPAGE_DISABLED => Interactions::NoopHandler,
    Slack::Identifiers::PREVIEW_SUBSCRIBE_DISABLED => Interactions::NoopHandler,
    Slack::Identifiers::HOME_ACTION_SELECT => Interactions::HomeActionSelectHandler
  }.freeze

  SHORTCUT_HANDLERS = {
    Slack::Identifiers::CREATE_INCIDENT_SHORTCUT => Interactions::CreateIncidentShortcutHandler
  }.freeze

  def self.dispatch(payload)
    interaction = Slack::InteractionNormalizer.call(payload)
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
