require "test_helper"

class EventDispatcherTest < ActiveSupport::TestCase
  test "routes reaction_added to ReactionAddedHandler" do
    payload = {
      "event" => { "type" => "reaction_added", "reaction" => "boom" },
      "team_id" => "T12345"
    }

    Events::ReactionAddedHandler.expects(:execute).with(Platforms::SLACK, payload).once

    EventDispatcher.dispatch(Platforms::SLACK, payload)
  end

  test "routes message to MessageHandler" do
    payload = {
      "event" => { "type" => "message" },
      "team_id" => "T12345"
    }

    Events::MessageHandler.expects(:execute).with(Platforms::SLACK, payload).once

    EventDispatcher.dispatch(Platforms::SLACK, payload)
  end

  test "routes pin_added to PinAddedHandler" do
    payload = {
      "event" => { "type" => "pin_added" },
      "team_id" => "T12345"
    }

    Events::PinAddedHandler.expects(:execute).with(Platforms::SLACK, payload).once

    EventDispatcher.dispatch(Platforms::SLACK, payload)
  end

  test "routes pin_removed to PinRemovedHandler" do
    payload = {
      "event" => { "type" => "pin_removed" },
      "team_id" => "T12345"
    }

    Events::PinRemovedHandler.expects(:execute).with(Platforms::SLACK, payload).once

    EventDispatcher.dispatch(Platforms::SLACK, payload)
  end

  test "routes member_joined_channel to MemberJoinedChannelHandler" do
    payload = {
      "event" => { "type" => "member_joined_channel" },
      "team_id" => "T12345"
    }

    Events::MemberJoinedChannelHandler.expects(:execute).with(Platforms::SLACK, payload).once

    EventDispatcher.dispatch(Platforms::SLACK, payload)
  end

  test "logs unhandled event types" do
    payload = {
      "event" => { "type" => "app_mention" },
      "team_id" => "T12345"
    }

    Rails.logger.expects(:info).once

    EventDispatcher.dispatch(Platforms::SLACK, payload)
  end

  test "ignores payload without event" do
    Events::ReactionAddedHandler.expects(:execute).never

    EventDispatcher.dispatch(Platforms::SLACK, {})
  end
end
