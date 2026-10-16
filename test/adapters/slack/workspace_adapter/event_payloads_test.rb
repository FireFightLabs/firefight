require "test_helper"

class Slack::WorkspaceAdapter::EventPayloadsTest < ActiveSupport::TestCase
  setup do
    @adapter = Slack::WorkspaceAdapter.new(workspaces(:slack_workspace_one))
  end

  test "a pin on a message reads as the message, its thread and who pinned it, and a pin on anything else as nothing" do
    pinned = { "event" => { "user" => "U1", "item" => { "type" => "message", "channel" => "C1", "message" => { "ts" => "1.2", "thread_ts" => "1.0" } } } }
    older = { "event" => { "user" => "U1", "item" => { "type" => "message", "channel" => "C1", "ts" => "3.4" } } }
    file = { "event" => { "user" => "U1", "item" => { "type" => "file", "channel" => "C1" } } }

    assert_equal({ channel_id: "C1", message_id: "1.2", thread_id: "1.0", user_id: "U1" }, @adapter.pinned_message(payload: pinned))
    assert_equal({ channel_id: "C1", message_id: "3.4", thread_id: nil, user_id: "U1" }, @adapter.pinned_message(payload: older))
    assert_nil @adapter.pinned_message(payload: file)
    assert_nil @adapter.pinned_message(payload: {})
  end

  test "a reaction reads as its emoji, the message it is on and who added it" do
    payload = { "event" => { "reaction" => "boom", "user" => "U1", "item" => { "channel" => "C1", "ts" => "1.2" } } }

    assert_equal({ emoji: "boom", channel_id: "C1", message_id: "1.2", user_id: "U1" }, @adapter.reaction(payload: payload))
    assert_equal({ emoji: nil, channel_id: nil, message_id: nil, user_id: nil }, @adapter.reaction(payload: {}))
  end

  test "a pressed button reads as the message it was on, with the message as posted handed back whole" do
    blocks = [ { "type" => "section", "text" => { "type" => "mrkdwn", "text" => "Paged" } } ]
    raw = { "container" => { "channel_id" => "D1", "message_ts" => "1.2" }, "message" => { "blocks" => blocks } }

    assert_equal({ channel_id: "D1", message_id: "1.2", content: blocks }, @adapter.pressed_message(raw: raw))
    assert_equal({ channel_id: nil, message_id: nil, content: [] }, @adapter.pressed_message(raw: nil))
  end
end
