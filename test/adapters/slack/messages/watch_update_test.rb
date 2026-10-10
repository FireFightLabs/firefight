require "test_helper"

class Slack::Messages::WatchUpdateTest < ActiveSupport::TestCase
  test "a line opens with its mark and the watch named for what it waits on, says the line below a divider, and escapes both" do
    update = Conversation::Watches::Said.new(id: "u1", watch_id: "w1", title: "Deploy <web> finished", name: 'Watch "Deploy <web> finished"',
                                             kind: Chat::Watch::Update::KIND_ENDED, tone: Conversation::Watches::TONE_FAILED, text: "It failed & stopped.",
                                             at: Time.current)

    blocks = Slack::Messages::WatchUpdate.build(update)

    assert_equal ":x:  *Watch \"Deploy &lt;web&gt; finished\"*", blocks.first.dig(:text, :text)
    assert_equal "divider", blocks.second[:type]
    assert_equal "It failed &amp; stopped.", blocks.third.dig(:text, :text)
    assert_equal 'Watch "Deploy <web> finished": It failed & stopped.', Slack::Messages::WatchUpdate.fallback(update)
  end

  test "a line said while the watch goes offers Stop, which asks first, the run's page, and Open the chat in a direct message" do
    update = Conversation::Watches::Said.new(id: "u2", watch_id: "w1", title: "Release run #46 passed", name: 'Watch "Release run #46 passed"',
                                             kind: Chat::Watch::Update::KIND_PROGRESS, tone: Chat::Watch::Update::KIND_PROGRESS, text: "Release run: tag passed.",
                                             at: Time.current, live: true, link: "https://github.com/acme/firefight/actions/runs/46")
    Slack::DashboardUrl.stubs(:agent_chat).returns("https://firefight.test/agent/c1")

    stop, run, open = Slack::Messages::WatchUpdate.build(update, direct: true, conversation_id: "c1").last[:elements]

    assert_equal [ Identifiers::WATCH_STOP, "u2", "Stop" ], [ stop[:action_id], stop[:value], stop.dig(:text, :text) ]
    assert_equal "Stop watching?", stop.dig(:confirm, :title, :text)
    assert_equal 'Halon stops watching "Release run #46 passed" and says so here. It will not report on it again.', stop.dig(:confirm, :text, :text)
    assert_equal [ "Open the run", "https://github.com/acme/firefight/actions/runs/46" ], [ run.dig(:text, :text), run[:url] ]
    assert_equal "https://firefight.test/agent/c1", open[:url]
  end

  test "a line said once the watch is over offers no Stop, and in a thread with no run page no actions at all" do
    update = Conversation::Watches::Said.new(id: "u3", watch_id: "w1", title: "release run #46", name: 'Watch "release run #46"', kind: Chat::Watch::Update::KIND_ENDED,
                                             tone: Conversation::Watches::TONE_STOPPED, text: "Bob stopped the watch.", at: Time.current)

    assert_equal %w[section divider section], Slack::Messages::WatchUpdate.build(update).map { |block| block[:type] }
  end
end
