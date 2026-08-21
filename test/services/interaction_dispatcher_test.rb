require "test_helper"

class InteractionDispatcherTest < ActiveSupport::TestCase
  # view_submission routing

  test "routes share_incidents_channel_modal to ShareModalSubmissionHandler" do
    interaction = Interaction.new(type: Interaction::VIEW_SUBMISSION, callback_id: Identifiers::SHARE_INCIDENTS_CHANNEL_MODAL)
    assert_equal Interactions::ShareModalSubmissionHandler, InteractionDispatcher.find(interaction)
  end

  test "routes incident_creation_modal to IncidentCreationHandler" do
    interaction = Interaction.new(type: Interaction::VIEW_SUBMISSION, callback_id: Identifiers::INCIDENT_CREATION_MODAL)
    assert_equal Interactions::IncidentCreationHandler, InteractionDispatcher.find(interaction)
  end

  test "routes incident_update_modal to IncidentUpdateHandler" do
    interaction = Interaction.new(type: Interaction::VIEW_SUBMISSION, callback_id: Identifiers::INCIDENT_UPDATE_MODAL)
    assert_equal Interactions::IncidentUpdateHandler, InteractionDispatcher.find(interaction)
  end

  test "routes escalate_incident_modal to EscalateIncident" do
    interaction = Interaction.new(type: Interaction::VIEW_SUBMISSION, callback_id: Identifiers::ESCALATE_INCIDENT_MODAL)
    assert_equal Interactions::EscalateIncidentHandler, InteractionDispatcher.find(interaction)
  end

  test "routes invite_responders_modal to InviteResponders" do
    interaction = Interaction.new(type: Interaction::VIEW_SUBMISSION, callback_id: Identifiers::INVITE_RESPONDERS_MODAL)
    assert_equal Interactions::InviteRespondersHandler, InteractionDispatcher.find(interaction)
  end

  test "routes unknown view_submission callback_id to UnknownHandler" do
    interaction = Interaction.new(type: Interaction::VIEW_SUBMISSION, callback_id: "unknown_modal")
    assert_equal Interactions::UnknownHandler, InteractionDispatcher.find(interaction)
  end

  # block_actions routing

  test "routes preview_announcement to PreviewAnnouncementHandler" do
    interaction = Interaction.new(type: Interaction::BLOCK_ACTIONS, action_id: Identifiers::PREVIEW_ANNOUNCEMENT)
    assert_equal Interactions::PreviewAnnouncementHandler, InteractionDispatcher.find(interaction)
  end

  test "routes share_incidents_channel to ShareChannelHandler" do
    interaction = Interaction.new(type: Interaction::BLOCK_ACTIONS, action_id: Identifiers::SHARE_INCIDENTS_CHANNEL)
    assert_equal Interactions::ShareChannelHandler, InteractionDispatcher.find(interaction)
  end

  test "routes preview_homepage_disabled to NoopHandler" do
    interaction = Interaction.new(type: Interaction::BLOCK_ACTIONS, action_id: Identifiers::PREVIEW_HOMEPAGE_DISABLED)
    assert_equal Interactions::NoopHandler, InteractionDispatcher.find(interaction)
  end

  test "routes preview_subscribe_disabled to NoopHandler" do
    interaction = Interaction.new(type: Interaction::BLOCK_ACTIONS, action_id: Identifiers::PREVIEW_SUBSCRIBE_DISABLED)
    assert_equal Interactions::NoopHandler, InteractionDispatcher.find(interaction)
  end

  test "routes home_action_select to HomeActionSelectHandler" do
    interaction = Interaction.new(type: Interaction::BLOCK_ACTIONS, action_id: Identifiers::HOME_ACTION_SELECT)
    assert_equal Interactions::HomeActionSelectHandler, InteractionDispatcher.find(interaction)
  end

  test "routes send_incident_update to SendIncidentUpdateButtonHandler" do
    interaction = Interaction.new(type: Interaction::BLOCK_ACTIONS, action_id: Identifiers::SEND_INCIDENT_UPDATE)
    assert_equal Interactions::SendIncidentUpdateButtonHandler, InteractionDispatcher.find(interaction)
  end

  test "routes escalate_incident to EscalateIncidentButtonHandler" do
    interaction = Interaction.new(type: Interaction::BLOCK_ACTIONS, action_id: Identifiers::ESCALATE_INCIDENT)
    assert_equal Interactions::EscalateIncidentButtonHandler, InteractionDispatcher.find(interaction)
  end

  test "routes pick_up_action to PickUpActionHandler" do
    interaction = Interaction.new(type: Interaction::BLOCK_ACTIONS, action_id: Identifiers::PICK_UP_ACTION)
    assert_equal Interactions::PickUpActionHandler, InteractionDispatcher.find(interaction)
  end

  test "routes mark_action_done to MarkActionDoneHandler" do
    interaction = Interaction.new(type: Interaction::BLOCK_ACTIONS, action_id: Identifiers::MARK_ACTION_DONE)
    assert_equal Interactions::MarkActionDoneHandler, InteractionDispatcher.find(interaction)
  end

  test "routes add_new_action to AddNewActionHandler" do
    interaction = Interaction.new(type: Interaction::BLOCK_ACTIONS, action_id: Identifiers::ADD_NEW_ACTION)
    assert_equal Interactions::AddNewActionHandler, InteractionDispatcher.find(interaction)
  end

  test "routes add_new_followup to AddNewFollowupHandler" do
    interaction = Interaction.new(type: Interaction::BLOCK_ACTIONS, action_id: Identifiers::ADD_NEW_FOLLOWUP)
    assert_equal Interactions::AddNewFollowupHandler, InteractionDispatcher.find(interaction)
  end

  test "routes create_action_from_reaction to CreateActionFromReactionHandler" do
    interaction = Interaction.new(type: Interaction::BLOCK_ACTIONS, action_id: Identifiers::CREATE_ACTION_FROM_REACTION)
    assert_equal Interactions::CreateActionFromReactionHandler, InteractionDispatcher.find(interaction)
  end

  test "routes create_followup_from_reaction to CreateFollowupFromReactionHandler" do
    interaction = Interaction.new(type: Interaction::BLOCK_ACTIONS, action_id: Identifiers::CREATE_FOLLOWUP_FROM_REACTION)
    assert_equal Interactions::CreateFollowupFromReactionHandler, InteractionDispatcher.find(interaction)
  end

  test "routes load_more_timeline to LoadMoreTimelineHandler" do
    interaction = Interaction.new(type: Interaction::BLOCK_ACTIONS, action_id: Identifiers::LOAD_MORE_TIMELINE)
    assert_equal Interactions::LoadMoreTimelineHandler, InteractionDispatcher.find(interaction)
  end

  test "routes acknowledge_escalation to AcknowledgeEscalationHandler" do
    interaction = Interaction.new(type: Interaction::BLOCK_ACTIONS, action_id: Identifiers::ACKNOWLEDGE_ESCALATION)
    assert_equal Interactions::AcknowledgeEscalationHandler, InteractionDispatcher.find(interaction)
  end

  test "routes create_action_modal to CreateActionHandler" do
    interaction = Interaction.new(type: Interaction::VIEW_SUBMISSION, callback_id: Identifiers::CREATE_ACTION_MODAL)
    assert_equal Interactions::CreateActionHandler, InteractionDispatcher.find(interaction)
  end

  test "routes create_followup_modal to CreateFollowupHandler" do
    interaction = Interaction.new(type: Interaction::VIEW_SUBMISSION, callback_id: Identifiers::CREATE_FOLLOWUP_MODAL)
    assert_equal Interactions::CreateFollowupHandler, InteractionDispatcher.find(interaction)
  end

  test "routes unknown block_actions action_id to UnknownHandler" do
    interaction = Interaction.new(type: Interaction::BLOCK_ACTIONS, action_id: "unknown_action")
    assert_equal Interactions::UnknownHandler, InteractionDispatcher.find(interaction)
  end

  # shortcut routing

  test "routes create_incident_shortcut to CreateIncidentShortcutHandler" do
    interaction = Interaction.new(type: Interaction::SHORTCUT, callback_id: Identifiers::CREATE_INCIDENT_SHORTCUT)
    assert_equal Interactions::CreateIncidentShortcutHandler, InteractionDispatcher.find(interaction)
  end

  test "routes unknown shortcut callback_id to UnknownHandler" do
    interaction = Interaction.new(type: Interaction::SHORTCUT, callback_id: "unknown_shortcut")
    assert_equal Interactions::UnknownHandler, InteractionDispatcher.find(interaction)
  end

  # view_closed routing

  test "routes view_closed to ViewClosedHandler" do
    interaction = Interaction.new(type: Interaction::VIEW_CLOSED)
    assert_equal Interactions::ViewClosedHandler, InteractionDispatcher.find(interaction)
  end

  # unknown type routing

  test "routes unknown type to UnknownHandler" do
    interaction = Interaction.new(type: "some_new_type")
    assert_equal Interactions::UnknownHandler, InteractionDispatcher.find(interaction)
  end

  # dispatch (end-to-end)

  test "dispatch calls handler and returns result" do
    interaction = Interaction.new(type: Interaction::VIEW_CLOSED)
    result = InteractionDispatcher.dispatch(interaction)
    assert_nil result
  end

  test "dispatch returns handler result for noop" do
    interaction = Interaction.new(type: Interaction::BLOCK_ACTIONS, action_id: Identifiers::PREVIEW_HOMEPAGE_DISABLED)
    result = InteractionDispatcher.dispatch(interaction)
    assert_equal "clear", result[:response_action]
  end

  # member provisioning

  test "dispatch provisions member before calling handler" do
    workspace = Workspace.create!(
      platform: "slack",
      platform_id: "T#{SecureRandom.hex(8)}",
      name: "Test Workspace",
      access_token: "xoxb-test-token",
      installed_at: Time.current,
      incidents_channel_id: "C12345678"
    )

    stub_get_user_info

    interaction = Interaction.new(
      type: Interaction::BLOCK_ACTIONS,
      action_id: Identifiers::HOME_ACTION_SELECT,
      platform: Platforms::SLACK,
      team_id: workspace.platform_id,
      user_id: "U_NEW_USER"
    )

    assert_difference "WorkspaceMembership.count", 1 do
      InteractionDispatcher.dispatch(interaction)
    end

    membership = workspace.workspace_memberships.find_by!(platform_user_id: "U_NEW_USER")
    assert_equal "member", membership.role
  end

  test "dispatch continues when provisioning fails" do
    interaction = Interaction.new(type: Interaction::VIEW_CLOSED)

    WorkspaceMemberProvisioner.stubs(:find_or_provision!).raises(StandardError.new("API down"))

    assert_nothing_raised do
      InteractionDispatcher.dispatch(interaction)
    end
  end
end
