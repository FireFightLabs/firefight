# Routes interactions to appropriate handlers based on type and callback/action ID
# Platform-agnostic — works with any Interaction object
class InteractionDispatcher
  VIEW_SUBMISSION_HANDLERS = {
    Identifiers::SHARE_INCIDENTS_CHANNEL_MODAL => Interactions::ShareModalSubmissionHandler,
    Identifiers::INCIDENT_CREATION_MODAL => Interactions::IncidentCreationHandler,
    Identifiers::UPDATE_SUMMARY_MODAL => Interactions::UpdateSummaryHandler,
    Identifiers::SET_LEAD_MODAL => Interactions::SetLeadHandler,
    Identifiers::INCIDENT_UPDATE_MODAL => Interactions::IncidentUpdateHandler,
    Identifiers::CREATE_ACTION_MODAL => Interactions::CreateActionHandler,
    Identifiers::CREATE_FOLLOWUP_MODAL => Interactions::CreateFollowupHandler,
    Identifiers::CLOSE_INCIDENT_MODAL => Interactions::CloseIncidentHandler,
    Identifiers::REOPEN_INCIDENT_MODAL => Interactions::ReopenIncidentHandler,
    Identifiers::LINK_INCIDENT_MODAL => Interactions::LinkIncidentHandler,
    Identifiers::ESCALATE_INCIDENT_MODAL => Interactions::EscalateIncidentHandler
  }.freeze

  BLOCK_ACTION_HANDLERS = {
    Identifiers::PREVIEW_ANNOUNCEMENT => Interactions::PreviewAnnouncementHandler,
    Identifiers::SHARE_INCIDENTS_CHANNEL => Interactions::ShareChannelHandler,
    Identifiers::PREVIEW_HOMEPAGE_DISABLED => Interactions::NoopHandler,
    Identifiers::PREVIEW_SUBSCRIBE_DISABLED => Interactions::NoopHandler,
    Identifiers::HOME_ACTION_SELECT => Interactions::HomeActionSelectHandler,
    Identifiers::SET_INCIDENT_LEAD_SELF => Interactions::SetLeadSelfHandler,
    Identifiers::UPDATE_INCIDENT_SUMMARY => Interactions::UpdateSummaryButtonHandler,
    Identifiers::ESCALATE_INCIDENT => Interactions::EscalateIncidentButtonHandler,
    Identifiers::SEND_INCIDENT_UPDATE => Interactions::SendIncidentUpdateButtonHandler,
    Identifiers::PICK_UP_ACTION => Interactions::PickUpActionHandler,
    Identifiers::MARK_ACTION_DONE => Interactions::MarkActionDoneHandler,
    Identifiers::ADD_NEW_ACTION => Interactions::AddNewActionHandler,
    Identifiers::ADD_NEW_FOLLOWUP => Interactions::AddNewFollowupHandler,
    Identifiers::CREATE_ACTION_FROM_REACTION => Interactions::CreateActionFromReactionHandler,
    Identifiers::CREATE_FOLLOWUP_FROM_REACTION => Interactions::CreateFollowupFromReactionHandler
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
