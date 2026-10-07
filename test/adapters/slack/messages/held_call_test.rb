require "test_helper"

class Slack::Messages::HeldCallTest < ActiveSupport::TestCase
  def shown(**overrides)
    Conversation::HeldCalls::Shown.new(**{
      id: "held-1", conversation_id: "chat-1", status: Chat::HeldCall::STATUS_READY,
      headline: "Ana approved: Api request on Faylee (Northflank), project faylee. Run it now?", call: "Api request",
      target: "Faylee (Northflank), project faylee", asked: [ [ "path", "/v1/services/<web>/scale" ] ],
      state: "web runs 2 of 2 instances on deploy 4f2a1c.", warning: "Things changed since this was asked for.", checked_at: Time.current,
      expires_at: Time.utc(2026, 10, 7, 15, 4), decided_by: nil, result: nil, offers: [ Chat::CurrentState::ACTION_RUN, Chat::CurrentState::ACTION_DISMISS ]
    }.merge(overrides))
  end

  test "an approved call asks to be run in its thread, under how things stand now, with when the approval expires" do
    blocks = Slack::Messages::HeldCall.build(shown)

    assert_equal ":unlock:  *Ana approved: Api request on Faylee (Northflank), project faylee. Run it now?*", blocks.first.dig(:text, :text)
    assert_equal "divider", blocks.second[:type]
    assert_equal "*Now:* web runs 2 of 2 instances on deploy 4f2a1c.\n:warning: Things changed since this was asked for.", blocks.third.dig(:text, :text)
    assert_equal "path: /v1/services/&lt;web&gt;/scale", blocks.fourth.dig(:elements, 0, :text)
    assert_includes blocks.fifth.dig(:elements, 0, :text), "Expires <!date^#{Time.utc(2026, 10, 7, 15, 4).to_i}^{time}|15:04 UTC>"
    buttons = blocks.last[:elements]
    assert_equal [ [ "Run", Identifiers::HELD_CALL_RUN, "primary" ], [ "Dismiss", Identifiers::HELD_CALL_DISMISS, nil ] ],
                 buttons.map { |button| [ button.dig(:text, :text), button[:action_id], button[:style] ] }
    assert_equal [ "held-1" ], buttons.map { |button| button[:value] }.uniq
  end

  test "while Halon checks there is no Run to press, and once it ran the buttons are gone and who ran it is named" do
    checking = Slack::Messages::HeldCall.build(shown(status: Chat::HeldCall::STATUS_CHECKING, state: nil, warning: nil))
    assert_equal Slack::Messages::HeldCall::CHECKING, checking.third.dig(:text, :text)
    assert_equal [ Identifiers::HELD_CALL_DISMISS ], checking.last[:elements].map { |button| button[:action_id] }

    ran = Slack::Messages::HeldCall.build(shown(status: Chat::HeldCall::STATUS_RAN, headline: "Ran Api request.", decided_by: "Ana", offers: []))
    assert_equal ":white_check_mark:  *Ran Api request.*", ran.first.dig(:text, :text)
    assert_equal "Run by Ana", ran.last.dig(:elements, 0, :text)
    assert ran.none? { |block| block[:type] == "actions" }
  end

  test "an expired one offers Ask again, and a denied one says who denied it and offers nothing" do
    expired = Slack::Messages::HeldCall.build(shown(status: Chat::HeldCall::STATUS_EXPIRED, offers: [ Chat::CurrentState::ACTION_ASK_AGAIN ]))
    assert_equal [ Identifiers::HELD_CALL_ASK_AGAIN ], expired.last[:elements].map { |button| button[:action_id] }

    denied = Slack::Messages::HeldCall.build(shown(status: Chat::HeldCall::STATUS_DENIED, headline: "Ana denied: Api request. Nothing ran.", offers: []))
    assert_equal ":no_entry_sign:  *Ana denied: Api request. Nothing ran.*", denied.first.dig(:text, :text)
    assert_equal "Ana denied: Api request. Nothing ran.", Slack::Messages::HeldCall.fallback(shown(headline: "Ana denied: Api request. Nothing ran."))
  end

  test "a direct message for a chat on the dashboard opens the chat instead of running anything from Slack" do
    ENV.stubs(:[]).returns(nil)
    ENV.stubs(:[]).with("APP_HOST").returns("ff.example")

    blocks = Slack::Messages::HeldCall.build(shown, direct: true)

    button = blocks.last[:elements].sole
    assert_equal [ "Open the chat", "https://ff.example/app/agent/chat-1" ], [ button.dig(:text, :text), button[:url] ]
    assert_nil button[:action_id]
  end
end
