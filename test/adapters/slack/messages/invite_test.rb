require "test_helper"

class Slack::Messages::InviteTest < ActiveSupport::TestCase
  test "names how many went in" do
    assert_equal "Invited 2 responders.", summary(invited: [ "U1", "U2" ])
    assert_equal "Invited 1 responder.", summary(invited: [ "U1" ])
  end

  test "names the people who were already here rather than counting them" do
    text = summary(invited: [ "U1" ], already_in_channel: [ "U2" ])

    assert_includes text, "Invited 1 responder."
    assert_includes text, "<@U2> is already in this channel."
  end

  # A round started from the dashboard holds members, one started from the
  # slash command holds platform ids, and both mention correctly.
  test "mentions a member the same as a platform id" do
    member = workspace_memberships(:alice_workspace_one)
    text = summary(already_in_channel: [ member ])

    assert_includes text, "<@#{member.platform_user_id}> is already in this channel."
  end

  test "reports failures alongside what did work" do
    text = summary(invited: [ "U1" ], failed: [ IncidentInviteService::Failure.new(person: "U3", error: "cant_invite") ])

    assert_includes text, "Invited 1 responder."
    assert_includes text, "1 failed."
  end

  test "says nothing happened rather than saying nothing" do
    assert_equal "No responders were invited.", summary
  end

  test "names the handles it could not resolve" do
    text = Slack::Messages::Invite.unresolved(
      user_ids: [], unresolved_handles: [ "nina" ], had_target_tokens: true
    )

    assert_includes text, "Couldn't resolve"
    assert_includes text, "@nina"
  end

  test "says nobody was named when nothing was typed" do
    text = Slack::Messages::Invite.unresolved(user_ids: [], unresolved_handles: [], had_target_tokens: false)

    assert_includes text, "No users specified"
  end

  private

  def summary(invited: [], already_in_channel: [], failed: [])
    Slack::Messages::Invite.summary(
      IncidentInviteService::Result.new(
        invited: invited, already_in_channel: already_in_channel, failed: failed
      )
    )
  end
end
