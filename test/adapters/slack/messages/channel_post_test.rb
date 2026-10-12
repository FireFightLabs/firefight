require "test_helper"

class Slack::Messages::ChannelPostTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
  end

  test "a post Halon wrote has the title, a divider, the message quoted line by line and who asked in the footer" do
    blocks = Slack::Messages::ChannelPost.build("Release 2.4 is out.\n\n- Faster search\n- Fewer pages", posted_by: @member, by_halon: true)

    assert_equal [ "section", "divider", "section", "context" ], blocks.map { |block| block[:type] }
    assert_equal ":mega:  *Message from Halon*", blocks.first.dig(:text, :text)
    assert_equal "> Release 2.4 is out.\n>\n> • Faster search\n> • Fewer pages", blocks[2].dig(:text, :text)
    assert_equal "Posted by Halon at the request of <@U87654321>", blocks.last.dig(:elements, 0, :text)
  end

  test "an outside agent's post names it in bold, since it has no Slack account" do
    agent = @workspace.agents.create!(name: "Release bot", slug: "release_bot")

    blocks = Slack::Messages::ChannelPost.build("Shipped", posted_by: agent, by_halon: false)

    assert_equal ":mega:  *Message from Firefight*", blocks.first.dig(:text, :text)
    assert_equal "Posted through Firefight by *Release bot*", blocks.last.dig(:elements, 0, :text)
  end

  test "words that would ping or fake a link are escaped, and a long message runs on into further sections" do
    blocks = Slack::Messages::ChannelPost.build("<!here> see <https://evil.example|bank>\n#{"A line of the release notes.\n" * 150}", posted_by: @member, by_halon: true)

    assert_match "&lt;!here&gt; see &lt;https://evil.example|bank&gt;", blocks[2].dig(:text, :text)
    bodies = blocks.select { |block| block[:type] == "section" }.drop(1)
    assert_operator bodies.size, :>, 1
    assert bodies.all? { |block| block.dig(:text, :text).length <= Slack::Messages::Formatting::SECTION_TEXT_LIMIT }
    assert_equal "Message from Halon: &lt;!here&gt; see &lt;https://evil.example|bank&gt;", Slack::Messages::ChannelPost.fallback("<!here> see <https://evil.example|bank>\nmore", by_halon: true)
  end
end
