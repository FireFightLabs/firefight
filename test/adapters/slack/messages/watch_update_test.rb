require "test_helper"

class Slack::Messages::WatchUpdateTest < ActiveSupport::TestCase
  test "a line opens with its mark and what is watched, says the line below a divider, and escapes both" do
    update = Conversation::Watches::Said.new(id: "u1", watch_id: "w1", title: "release <run> #46", kind: Chat::Watch::Update::KIND_ENDED,
                                             tone: Conversation::Watches::TONE_FAILED, text: "It failed & stopped.", at: Time.current)

    blocks = Slack::Messages::WatchUpdate.build(update)

    assert_equal ":x:  *Watching release &lt;run&gt; #46*", blocks.first.dig(:text, :text)
    assert_equal "divider", blocks.second[:type]
    assert_equal "It failed &amp; stopped.", blocks.third.dig(:text, :text)
    assert_equal "Watching release <run> #46: It failed & stopped.", Slack::Messages::WatchUpdate.fallback(update)
  end
end
