require "test_helper"

class InteractionDispatcherTest < ActiveSupport::TestCase
  # view_submission routing

  test "routes share_incidents_channel_modal to ShareModalSubmissionHandler" do
    payload = { "type" => "view_submission", "view" => { "callback_id" => Slack::Identifiers::SHARE_INCIDENTS_CHANNEL_MODAL } }
    assert_equal Interactions::ShareModalSubmissionHandler, InteractionDispatcher.find(payload)
  end

  test "routes unknown view_submission callback_id to UnknownHandler" do
    payload = { "type" => "view_submission", "view" => { "callback_id" => "unknown_modal" } }
    assert_equal Interactions::UnknownHandler, InteractionDispatcher.find(payload)
  end

  # block_actions routing

  test "routes preview_announcement to PreviewAnnouncementHandler" do
    payload = { "type" => "block_actions", "actions" => [ { "action_id" => Slack::Identifiers::PREVIEW_ANNOUNCEMENT } ] }
    assert_equal Interactions::PreviewAnnouncementHandler, InteractionDispatcher.find(payload)
  end

  test "routes share_incidents_channel to ShareChannelHandler" do
    payload = { "type" => "block_actions", "actions" => [ { "action_id" => Slack::Identifiers::SHARE_INCIDENTS_CHANNEL } ] }
    assert_equal Interactions::ShareChannelHandler, InteractionDispatcher.find(payload)
  end

  test "routes preview_homepage_disabled to NoopHandler" do
    payload = { "type" => "block_actions", "actions" => [ { "action_id" => Slack::Identifiers::PREVIEW_HOMEPAGE_DISABLED } ] }
    assert_equal Interactions::NoopHandler, InteractionDispatcher.find(payload)
  end

  test "routes preview_subscribe_disabled to NoopHandler" do
    payload = { "type" => "block_actions", "actions" => [ { "action_id" => Slack::Identifiers::PREVIEW_SUBSCRIBE_DISABLED } ] }
    assert_equal Interactions::NoopHandler, InteractionDispatcher.find(payload)
  end

  test "routes unknown block_actions action_id to UnknownHandler" do
    payload = { "type" => "block_actions", "actions" => [ { "action_id" => "unknown_action" } ] }
    assert_equal Interactions::UnknownHandler, InteractionDispatcher.find(payload)
  end

  # shortcut routing

  test "routes create_incident_shortcut to CreateIncidentShortcutHandler" do
    payload = { "type" => "shortcut", "callback_id" => Slack::Identifiers::CREATE_INCIDENT_SHORTCUT }
    assert_equal Interactions::CreateIncidentShortcutHandler, InteractionDispatcher.find(payload)
  end

  test "routes unknown shortcut callback_id to UnknownHandler" do
    payload = { "type" => "shortcut", "callback_id" => "unknown_shortcut" }
    assert_equal Interactions::UnknownHandler, InteractionDispatcher.find(payload)
  end

  # view_closed routing

  test "routes view_closed to ViewClosedHandler" do
    payload = { "type" => "view_closed" }
    assert_equal Interactions::ViewClosedHandler, InteractionDispatcher.find(payload)
  end

  # unknown type routing

  test "routes unknown type to UnknownHandler" do
    payload = { "type" => "some_new_type" }
    assert_equal Interactions::UnknownHandler, InteractionDispatcher.find(payload)
  end

  # dispatch

  test "dispatch calls execute on the found handler" do
    payload = { "type" => "view_closed" }
    result = InteractionDispatcher.dispatch(payload)
    assert_nil result
  end

  test "dispatch returns handler result for noop" do
    payload = { "type" => "block_actions", "actions" => [ { "action_id" => Slack::Identifiers::PREVIEW_HOMEPAGE_DISABLED } ] }
    result = InteractionDispatcher.dispatch(payload)
    assert_equal "clear", result[:response_action]
  end
end
