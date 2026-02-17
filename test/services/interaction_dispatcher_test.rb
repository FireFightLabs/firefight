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
end
