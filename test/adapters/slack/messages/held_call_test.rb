require "test_helper"

class Slack::Messages::HeldCallTest < ActiveSupport::TestCase
  def shown(**overrides)
    Conversation::HeldCalls::Shown.new(**{
      id: "held-1", conversation_id: "chat-1", status: Chat::HeldCall::STATUS_WAITING, headline: "Halon wants to: scale web to zero",
      call: "Api request", target: "Faylee (Northflank), project faylee", asked: [ [ "path", "/v1/services/<web>/scale" ] ],
      state: nil, warning: nil, checked_at: nil, expires_at: nil, decided_by: nil, result: nil, offers: [], action: "scale web to zero",
      line: "Waiting for a workspace admin to approve it.", approval_id: "approval-1", approved_by: nil, progress: nil, link: nil
    }.merge(overrides))
  end

  def buttons(blocks) = blocks.flat_map { |block| block[:actions] || block[:elements] || [] }.select { |element| element[:type] == "button" }

  test "while it waits it is a request in the thread, with Approve and Deny for its approvers and the call under Details" do
    blocks = Slack::Messages::HeldCall.build(shown, rich: true)

    card = blocks.sole
    assert_equal "card", card[:type]
    assert_equal ":raised_hand:  Halon wants to: scale web to zero", card.dig(:title, :text)
    assert_equal "Waiting for a workspace admin to approve it.", card.dig(:body, :text)
    assert_equal [ [ "Approve", Identifiers::APPROVE_ABILITY, "approval-1" ], [ "Deny", Identifiers::DENY_ABILITY, "approval-1" ],
                   [ "Details", Identifiers::HELD_CALL_DETAILS, "held-1" ] ],
                 card[:actions].map { |button| [ button.dig(:text, :text), button[:action_id], button[:value] ] }
    assert_no_match(/scale"|services/, blocks.to_json, "the call itself is under Details")
  end

  test "a workspace whose Slack refuses cards gets the same words as plain blocks" do
    blocks = Slack::Messages::HeldCall.build(shown, rich: false)

    assert_equal [ "section", "actions" ], blocks.map { |block| block[:type] }
    assert_equal "*:raised_hand:  Halon wants to: scale web to zero*\nWaiting for a workspace admin to approve it.", blocks.first.dig(:text, :text)
  end

  test "while an approved code change runs, the message is its checklist with who approved it" do
    work = Chat::CodeFixProgress.start
    work.changed!("app/a.rb")
    work.tested!("bin/rails test", passed: true)

    blocks = Slack::Messages::HeldCall.build(shown(status: Chat::HeldCall::STATUS_RUNNING, headline: "Scale web to zero", approved_by: "Ana", progress: work), rich: true)

    plan = blocks.first
    assert_equal [ "plan", "Scale web to zero" ], [ plan[:type], plan[:title] ]
    assert_equal [ [ "Write the change", "complete" ], [ "Check the change", "complete" ], [ "Open a pull request", "in_progress" ] ],
                 plan[:tasks].map { |task| [ task[:title], task[:status] ] }
    assert_equal "Approved by Ana", blocks.second.dig(:elements, 0, :text)
    assert_equal [ Identifiers::HELD_CALL_DETAILS ], buttons(blocks).map { |button| button[:action_id] }
  end

  test "any other change says in one line that it is under way" do
    blocks = Slack::Messages::HeldCall.build(shown(status: Chat::HeldCall::STATUS_RUNNING, headline: "Scale web to zero", approved_by: "Ana"), rich: true)

    assert_equal "Approved by Ana  ·  working…", blocks.sole.dig(:body, :text)
  end

  test "once it ran, one line says it is done with the page it made, and a failure says why" do
    done = Slack::Messages::HeldCall.build(shown(status: Chat::HeldCall::STATUS_RAN, headline: "Done: scale web to zero", line: "Approved by Ana.",
                                                 link: "https://github.com/acme/shop/pull/856"), rich: true).sole
    assert_equal ":white_check_mark:  Done: scale web to zero", done.dig(:title, :text)
    assert_equal "Approved by Ana.  ·  <https://github.com/acme/shop/pull/856|github.com/acme/shop/pull/856>", done.dig(:body, :text)
    assert_equal [ Identifiers::HELD_CALL_DETAILS ], done[:actions].map { |button| button[:action_id] }

    failed = Slack::Messages::HeldCall.build(shown(status: Chat::HeldCall::STATUS_FAILED, headline: "Failed: scale web to zero", line: "The service was not found."), rich: true).sole
    assert_equal [ ":x:  Failed: scale web to zero", "The service was not found." ], [ failed.dig(:title, :text), failed.dig(:body, :text) ]

    denied = Slack::Messages::HeldCall.build(shown(status: Chat::HeldCall::STATUS_DENIED, headline: "Denied: scale web to zero", line: "Denied by Ana. Nothing ran."), rich: true).sole
    assert_equal ":no_entry_sign:  Denied: scale web to zero", denied.dig(:title, :text)
  end

  test "a call approved before approving ran it still asks to be run, under how things stand now and when it expires" do
    ready = shown(status: Chat::HeldCall::STATUS_READY, line: "Approved by Ana. Run it now?", state: "web runs 2 of 2 instances.",
                  warning: "Things changed since this was asked for.", expires_at: Time.utc(2026, 10, 7, 15, 4),
                  offers: [ Chat::CurrentState::ACTION_RUN, Chat::CurrentState::ACTION_DISMISS ])

    card = Slack::Messages::HeldCall.build(ready, rich: false)

    assert_includes card.first.dig(:text, :text), "Approved by Ana. Run it now?  ·  :warning: Things changed since this was asked for.  ·  Now: web runs 2 of 2 instances."
    assert_includes card.first.dig(:text, :text), "Expires <!date^#{Time.utc(2026, 10, 7, 15, 4).to_i}^{time}|15:04 UTC>"
    assert_equal [ Identifiers::HELD_CALL_RUN, Identifiers::HELD_CALL_DISMISS, Identifiers::HELD_CALL_DETAILS ], buttons(card).map { |button| button[:action_id] }

    checking = Slack::Messages::HeldCall.build(ready.with(status: Chat::HeldCall::STATUS_CHECKING), rich: false)
    assert_equal [ Identifiers::HELD_CALL_DISMISS, Identifiers::HELD_CALL_DETAILS ], buttons(checking).map { |button| button[:action_id] }

    expired = Slack::Messages::HeldCall.build(ready.with(status: Chat::HeldCall::STATUS_EXPIRED, offers: [ Chat::CurrentState::ACTION_ASK_AGAIN ]), rich: false)
    assert_equal [ Identifiers::HELD_CALL_ASK_AGAIN, Identifiers::HELD_CALL_DETAILS ], buttons(expired).map { |button| button[:action_id] }
  end

  test "a direct message for a chat on the dashboard opens the chat instead of running anything from Slack" do
    ENV.stubs(:[]).returns(nil)
    ENV.stubs(:[]).with("APP_HOST").returns("ff.example")

    blocks = Slack::Messages::HeldCall.build(shown, direct: true, rich: false)

    open, details = buttons(blocks)
    assert_equal [ "Open the chat", "https://ff.example/app/agent/chat-1" ], [ open.dig(:text, :text), open[:url] ]
    assert_equal Identifiers::HELD_CALL_DETAILS, details[:action_id]
  end

  test "Details shows the call as it was given, escaped" do
    view = Slack::Modals::HeldCallDetails.build(shown)

    text = view[:blocks].map { |block| block.dig(:text, :text) }.join("\n")
    assert_includes text, "Api request on Faylee (Northflank), project faylee"
    assert_includes text, "path: /v1/services/&lt;web&gt;/scale"
  end
end
