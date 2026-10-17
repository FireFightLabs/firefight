require "test_helper"

class Slack::Messages::WatchCardTest < ActiveSupport::TestCase
  RUN = "https://github.com/acme/firefight/actions/runs/46".freeze

  test "a watch going is a card naming what it is for, Watching and the step it is on, with Stop, the run and the chat" do
    Slack::DashboardUrl.stubs(:agent_chat).with("c1").returns("https://firefight.test/agent/c1")
    card = card_of(status: Chat::Watch::STATUS_ACTIVE, what: "Ship <main>", why: "Release run #46 is running.", link: RUN, conversation_id: "c1")

    block = Slack::Messages::WatchCard.build(card, rich: true).sole

    assert_equal [ "card", ":eyes:  Ship &lt;main&gt;", "Watching", "Release run #46 is running." ],
                 [ block[:type], block.dig(:title, :text), block.dig(:subtitle, :text), block.dig(:body, :text) ]
    stop, run, open = block[:actions]
    assert_equal [ Identifiers::WATCH_STOP, "u1", "Stop" ], [ stop[:action_id], stop[:value], stop.dig(:text, :text) ]
    assert_equal "Stop watching?", stop.dig(:confirm, :title, :text)
    assert_equal "Halon stops watching this and says so here. It will not report on it again.", stop.dig(:confirm, :text, :text)
    assert_equal [ "Open the run", RUN ], [ run.dig(:text, :text), run[:url] ]
    assert_equal [ "Open the chat", "https://firefight.test/agent/c1" ], [ open.dig(:text, :text), open[:url] ]
    assert_equal "Watching: Ship <main>. Release run #46 is running.", Slack::Messages::WatchCard.fallback(card)
  end

  test "an ended watch says how it ended and why, and offers only the run and the chat" do
    Slack::DashboardUrl.stubs(:agent_chat).returns("https://firefight.test/agent/c1")
    {
      Chat::Watch::STATUS_SUCCEEDED => [ ":white_check_mark:", "Done" ], Chat::Watch::STATUS_FAILED => [ ":x:", "Failed" ],
      Chat::Watch::STATUS_TIMED_OUT => [ ":hourglass:", "Timed out" ], Chat::Watch::STATUS_STOPPED => [ ":octagonal_sign:", "Stopped" ]
    }.each do |status, (icon, state)|
      block = Slack::Messages::WatchCard.build(card_of(status: status, state: state, link: RUN, conversation_id: "c1"), rich: true).sole

      assert_equal [ "#{icon}  Deploy finished", state ], [ block.dig(:title, :text), block.dig(:subtitle, :text) ]
      assert_equal [ "Open the run", "Open the chat" ], block[:actions].map { |button| button.dig(:text, :text) }
    end
  end

  test "a workspace that does not show cards gets the same words as a section, a context line and the buttons" do
    blocks = Slack::Messages::WatchCard.build(card_of(status: Chat::Watch::STATUS_ACTIVE, why: "Web deploy is running & nearly there."), rich: false)

    assert_equal %w[section context actions], blocks.map { |block| block[:type] }
    assert_equal "*:eyes:  Deploy finished*\nWeb deploy is running &amp; nearly there.", blocks.first.dig(:text, :text)
    assert_equal "Watching", blocks.second[:elements].sole[:text]
    assert_equal [ Identifiers::WATCH_STOP ], blocks.third[:elements].map { |button| button[:action_id] }
  end

  test "how it ended is one short line of its own, so the person hears it, led by its mark" do
    card = card_of(status: Chat::Watch::STATUS_SUCCEEDED, state: "Done", what: "Ship main", why: "Took 7 minutes. web is serving 7676c83.")

    assert_equal [ { type: "section", text: { type: "mrkdwn", text: ":white_check_mark:  *Done: Ship main.* Took 7 minutes. web is serving 7676c83." } } ],
                 Slack::Messages::WatchCard.ended(card)
    assert_equal "Done: Ship main. Took 7 minutes. web is serving 7676c83.", Slack::Messages::WatchCard.fallback(card)
  end

  private

  def card_of(status:, state: "Watching", what: "Deploy finished", why: "Web deploy is running.", link: nil, conversation_id: nil)
    Conversation::Watches::Card.new(watch_id: "w1", update_id: "u1", status: status, state: state, what: what, why: why, link: link,
                                    conversation_id: conversation_id)
  end
end
