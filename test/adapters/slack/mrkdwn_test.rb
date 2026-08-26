require "test_helper"

class Slack::MrkdwnTest < ActiveSupport::TestCase
  test "mentions a person by their platform account" do
    member = workspace_memberships(:alice_workspace_one)

    assert_equal "<@#{member.platform_user_id}>", Slack::Mrkdwn.mention(member)
  end

  # A machine has no Slack account, so an empty <@> would render as a broken
  # mention where its name belongs.
  test "names a machine instead of rendering an empty mention" do
    agent = workspaces(:slack_workspace_one).agents.create!(name: "Support agent", slug: "support_agent")

    assert_equal "*Support agent*", Slack::Mrkdwn.mention(agent)
  end

  test "escapes a machine name that would otherwise inject markup" do
    agent = workspaces(:slack_workspace_one).agents.create!(name: "<!channel>", slug: "sneaky")

    assert_equal "*&lt;!channel&gt;*", Slack::Mrkdwn.mention(agent)
  end

  test "nobody is someone" do
    assert_equal "someone", Slack::Mrkdwn.mention(nil)
  end
end
