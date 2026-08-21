# Routes interactions to appropriate handlers based on type and callback/action ID
# Platform-agnostic — works with any Interaction object
class InteractionDispatcher
  VIEW_SUBMISSION_HANDLERS = {
    Identifiers::INCIDENT_HOME_MODAL => Interactions::HomeContinueHandler,
    Identifiers::SHARE_INCIDENTS_CHANNEL_MODAL => Interactions::ShareModalSubmissionHandler,
    Identifiers::INCIDENT_CREATION_MODAL => Interactions::IncidentCreationHandler,
    Identifiers::UPDATE_SUMMARY_MODAL => Interactions::UpdateSummaryHandler,
    Identifiers::SET_LEAD_MODAL => Interactions::SetLeadHandler,
    Identifiers::SET_ROLES_MODAL => Interactions::SetRolesHandler,
    Identifiers::INCIDENT_UPDATE_MODAL => Interactions::IncidentUpdateHandler,
    Identifiers::CREATE_ACTION_MODAL => Interactions::CreateActionHandler,
    Identifiers::CREATE_FOLLOWUP_MODAL => Interactions::CreateFollowupHandler,
    Identifiers::CANCEL_INCIDENT_MODAL => Interactions::CancelIncidentHandler,
    Identifiers::CLOSE_INCIDENT_MODAL => Interactions::CloseIncidentHandler,
    Identifiers::REOPEN_INCIDENT_MODAL => Interactions::ReopenIncidentHandler,
    Identifiers::LINK_INCIDENT_MODAL => Interactions::LinkIncidentHandler,
    Identifiers::ATTACH_RUNBOOK_MODAL => Interactions::AttachRunbookHandler,
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
    Identifiers::CANCEL_INCIDENT => Interactions::CancelIncidentButtonHandler,
    Identifiers::SET_INCIDENT_LEAD_SELF => Interactions::SetLeadSelfHandler,
    Identifiers::UPDATE_INCIDENT_SUMMARY => Interactions::UpdateSummaryButtonHandler,
    Identifiers::ESCALATE_INCIDENT => Interactions::EscalateIncidentButtonHandler,
    Identifiers::SEND_INCIDENT_UPDATE => Interactions::SendIncidentUpdateButtonHandler,
    Identifiers::PICK_UP_ACTION => Interactions::PickUpActionHandler,
    Identifiers::MARK_ACTION_DONE => Interactions::MarkActionDoneHandler,
    Identifiers::REASSIGN_ACTION => Interactions::ReassignActionHandler,
    Identifiers::CLAIM_RUNBOOK_STEP => Interactions::ClaimRunbookStepHandler,
    Identifiers::VIEW_RUNBOOK => Interactions::ViewRunbookHandler,
    Identifiers::ASSIGN_RUNBOOK_STEP => Interactions::AssignRunbookStepHandler,
    Identifiers::ADD_NEW_ACTION => Interactions::AddNewActionHandler,
    Identifiers::ADD_NEW_FOLLOWUP => Interactions::AddNewFollowupHandler,
    Identifiers::CREATE_ACTION_FROM_REACTION => Interactions::CreateActionFromReactionHandler,
    Identifiers::CREATE_FOLLOWUP_FROM_REACTION => Interactions::CreateFollowupFromReactionHandler,
    Identifiers::LOAD_MORE_TIMELINE => Interactions::LoadMoreTimelineHandler,
    Identifiers::ACKNOWLEDGE_ESCALATION => Interactions::AcknowledgeEscalationHandler,
    Identifiers::SHOUTOUT_FROM_REACTION => Interactions::ShoutoutFromReactionHandler,
    Identifiers::INCIDENT_CREATION_SEVERITY_SELECT => Interactions::IncidentCreationSelectHandler,
    Identifiers::INCIDENT_CREATION_TYPE_SELECT => Interactions::IncidentCreationSelectHandler,
    Identifiers::INCIDENT_CREATION_VISIBILITY_SELECT => Interactions::IncidentCreationSelectHandler,
    Identifiers::APPLY_RUNBOOK => Interactions::ApplyRunbookHandler,
    Identifiers::APPROVE_ABILITY => Interactions::ApproveAbilityHandler,
    Identifiers::DENY_ABILITY => Interactions::DenyAbilityHandler
  }.freeze

  SHORTCUT_HANDLERS = {
    Identifiers::CREATE_INCIDENT_SHORTCUT => Interactions::CreateIncidentShortcutHandler
  }.freeze

  def self.dispatch(interaction)
    handler = find(interaction)
    OpenTelemetry::Trace.current_span.add_attributes({
      "slack.interaction_type" => interaction.type,
      "slack.callback_id" => interaction.callback_id,
      "slack.action_id" => interaction.action_id,
      "slack.handler" => handler.name
    }.compact)

    AuthorizedDispatch.call(handler, interaction, context: { incident_id: interaction.incident_id }) do
      handler.execute(interaction)
    end
  rescue AuthorizedDispatch::PrincipalUnresolved
    refuse(interaction, AuthorizedDispatch::UNRESOLVED_MESSAGE)
  rescue AbilityGateway::Denied => e
    refuse(interaction, AuthorizedDispatch.denied_message(e))
  rescue AbilityGateway::PendingApproval => e
    ApprovalResumption.park!(e.approval, interaction, ApprovalResumption::KIND_INTERACTION)
    refuse(interaction, AuthorizedDispatch.pending_message(e.approval))
  end

  # A refused interaction closes its modal and explains itself where the person
  # is looking. A button click carries its channel; a modal submission does
  # not, so it falls back to the incident the modal was opened against.
  def self.refuse(interaction, text)
    workspace = interaction.workspace
    channel_id = interaction.channel_id.presence || refusal_channel(workspace, interaction)
    return nil if channel_id.blank?

    workspace.adapter.post_ephemeral(channel_id: channel_id, user_id: interaction.user_id, text: text)
    nil
  rescue AdapterError, ActiveRecord::RecordNotFound => e
    Rails.logger.warn({ event: "interaction_dispatcher.refusal_undelivered", error: e.class.name }.to_json)
    nil
  end
  private_class_method :refuse

  def self.refusal_channel(workspace, interaction)
    incident_id = interaction.incident_id
    return workspace.incidents_channel_id if incident_id.blank?

    workspace.incidents.find_by(id: incident_id)&.channel_id.presence || workspace.incidents_channel_id
  end
  private_class_method :refusal_channel

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
