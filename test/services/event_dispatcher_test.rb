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

  test "logs unhandled event types" do
    payload = {
      "event" => { "type" => "message" },
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
