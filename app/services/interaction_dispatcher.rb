# Routes interactions to appropriate handlers based on type and callback/action ID
# Platform-agnostic — works with any Interaction object
class InteractionDispatcher
  VIEW_SUBMISSION_HANDLERS = {
    Identifiers::INCIDENT_HOME_MODAL => Interactions::HomeContinueHandler,
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
    Identifiers::ESCALATE_INCIDENT_MODAL => Interactions::EscalateIncidentHandler,
    Identifiers::INVITE_RESPONDERS_MODAL => Interactions::InviteRespondersHandler,
    Identifiers::SHOUTOUT_MODAL => Interactions::ShoutoutHandler
  }.freeze

  BLOCK_ACTION_HANDLERS = {
    Identifiers::PREVIEW_ANNOUNCEMENT => Interactions::PreviewAnnouncementHandler,
    Identifiers::SHARE_INCIDENTS_CHANNEL => Interactions::ShareChannelHandler,
    Identifiers::PREVIEW_HOMEPAGE_DISABLED => Interactions::NoopHandler,
    Identifiers::PREVIEW_SUBSCRIBE_DISABLED => Interactions::NoopHandler,
    Identifiers::HOME_ACTION_SELECT => Interactions::HomeActionSelectHandler,
    Identifiers::ACCEPT_INCIDENT => Interactions::AcceptIncidentHandler,
    Identifiers::SET_INCIDENT_LEAD_SELF => Interactions::SetLeadSelfHandler,
    Identifiers::UPDATE_INCIDENT_SUMMARY => Interactions::UpdateSummaryButtonHandler,
    Identifiers::ESCALATE_INCIDENT => Interactions::EscalateIncidentButtonHandler,
    Identifiers::SEND_INCIDENT_UPDATE => Interactions::SendIncidentUpdateButtonHandler,
    Identifiers::PICK_UP_ACTION => Interactions::PickUpActionHandler,
    Identifiers::MARK_ACTION_DONE => Interactions::MarkActionDoneHandler,
    Identifiers::ADD_NEW_ACTION => Interactions::AddNewActionHandler,
    Identifiers::ADD_NEW_FOLLOWUP => Interactions::AddNewFollowupHandler,
    Identifiers::CREATE_ACTION_FROM_REACTION => Interactions::CreateActionFromReactionHandler,
    Identifiers::CREATE_FOLLOWUP_FROM_REACTION => Interactions::CreateFollowupFromReactionHandler,
    Identifiers::LOAD_MORE_TIMELINE => Interactions::LoadMoreTimelineHandler,
    Identifiers::ACKNOWLEDGE_ESCALATION => Interactions::AcknowledgeEscalationHandler,
    Identifiers::SHOUTOUT_FROM_REACTION => Interactions::ShoutoutFromReactionHandler,
    Identifiers::INCIDENT_CREATION_SEVERITY_SELECT => Interactions::IncidentCreationSeveritySelectHandler,
    Identifiers::INCIDENT_CREATION_TYPE_SELECT => Interactions::IncidentCreationTypeSelectHandler
  }.freeze

  SHORTCUT_HANDLERS = {
    Identifiers::CREATE_INCIDENT_SHORTCUT => Interactions::CreateIncidentShortcutHandler
  }.freeze

  def self.dispatch(interaction)
    ensure_member_provisioned(interaction)
    handler = find(interaction)
    OpenTelemetry::Trace.current_span.add_attributes({
      "slack.interaction_type" => interaction.type,
      "slack.callback_id" => interaction.callback_id,
      "slack.action_id" => interaction.action_id,
      "slack.handler" => handler.name
    }.compact)
    handler.execute(interaction)
  end

  def self.ensure_member_provisioned(interaction)
    workspace = interaction.workspace
    WorkspaceMemberProvisioner.find_or_provision!(
      workspace: workspace,
      platform_user_id: interaction.user_id,
      adapter: workspace.adapter
    )
  rescue StandardError => e
    Rails.logger.warn({
      event: "interaction_dispatcher.provisioning_failed",
      user_id: interaction.user_id,
      error: e.message
    })
  end
  private_class_method :ensure_member_provisioned

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
