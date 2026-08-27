require "test_helper"

class EventDispatcherTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "routes reaction_added to ReactionAddedHandler" do
    payload = {
      "event" => { "type" => "reaction_added", "reaction" => "boom" },
      "team_id" => @workspace.platform_id
    }

    Events::ReactionAddedHandler.expects(:execute).with(@workspace, payload).once

    EventDispatcher.dispatch(Platforms::SLACK, payload)
  end

  test "routes message to MessageHandler" do
    payload = {
      "event" => { "type" => "message" },
      "team_id" => @workspace.platform_id
    }

    Events::MessageHandler.expects(:execute).with(@workspace, payload).once

    EventDispatcher.dispatch(Platforms::SLACK, payload)
  end

  test "routes pin_added to PinAddedHandler" do
    payload = {
      "event" => { "type" => "pin_added" },
      "team_id" => @workspace.platform_id
    }

    Events::PinAddedHandler.expects(:execute).with(@workspace, payload).once

    EventDispatcher.dispatch(Platforms::SLACK, payload)
  end

  test "routes pin_removed to PinRemovedHandler" do
    payload = {
      "event" => { "type" => "pin_removed" },
      "team_id" => @workspace.platform_id
    }

    Events::PinRemovedHandler.expects(:execute).with(@workspace, payload).once

    EventDispatcher.dispatch(Platforms::SLACK, payload)
  end

  test "routes member_joined_channel to MemberJoinedChannelHandler" do
    payload = {
      "event" => { "type" => "member_joined_channel" },
      "team_id" => @workspace.platform_id
    }

    Events::MemberJoinedChannelHandler.expects(:execute).with(@workspace, payload).once

    EventDispatcher.dispatch(Platforms::SLACK, payload)
  end

  test "logs unhandled event types" do
    payload = {
      "event" => { "type" => "channel_created" },
      "team_id" => @workspace.platform_id
    }

    Rails.logger.expects(:info).once

    EventDispatcher.dispatch(Platforms::SLACK, payload)
  end

  test "ignores payload without event" do
    Events::ReactionAddedHandler.expects(:execute).never

    EventDispatcher.dispatch(Platforms::SLACK, {})
  end

  test "an event from a workspace Firefight does not know is dropped before any handler" do
    payload = { "event" => { "type" => "message" }, "team_id" => "T_NOBODY" }
    Events::MessageHandler.expects(:execute).never

    EventDispatcher.dispatch(Platforms::SLACK, payload)
  end

  test "an adapter failure is logged and done, anything else propagates for the job to retry" do
    payload = { "event" => { "type" => "message" }, "team_id" => @workspace.platform_id }

    Events::MessageHandler.stubs(:execute).raises(AdapterError, "slack said no")
    assert_nothing_raised { EventDispatcher.dispatch(Platforms::SLACK, payload) }

    Events::MessageHandler.stubs(:execute).raises(ActiveRecord::ConnectionNotEstablished)
    assert_raises(ActiveRecord::ConnectionNotEstablished) { EventDispatcher.dispatch(Platforms::SLACK, payload) }
  end
end
