require "test_helper"

class Slack::MrkdwnTest < ActiveSupport::TestCase
  test "mentions a person by their platform account" do
    member = workspace_memberships(:alice_workspace_one)

    assert_equal "<@#{member.platform_user_id}>", Slack::Mrkdwn.mention(member)
  end

  # A machine has no Slack account, so an empty <@> would render as a broken mention.
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

  test "a person with no Slack account is named, not given an empty mention" do
    seat = workspaces(:slack_workspace_one).workspace_memberships.create!(
      user: User.create!(email: "web-only@example.com", name: "Wendy Web"), role: :member, joined_at: Time.current
    )

    assert_equal "*Wendy Web*", Slack::Mrkdwn.mention(seat)
  end

  test "an id and a name read the same way, with the mention bolded only when asked" do
    assert_equal "<@U1>", Slack::Mrkdwn.person("U1", "Ignored")
    assert_equal "*<@U1>*", Slack::Mrkdwn.person("U1", nil, bold: true)
    assert_equal "*Wendy Web*", Slack::Mrkdwn.person(nil, "Wendy Web", bold: true)
    assert_equal "*&lt;b&gt;*", Slack::Mrkdwn.person("", "<b>")
    assert_equal "someone", Slack::Mrkdwn.person(nil, nil)
  end
end
