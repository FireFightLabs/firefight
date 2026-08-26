require "test_helper"

class Slack::Messages::InviteTest < ActiveSupport::TestCase
  test "names how many went in" do
    assert_equal "Invited 2 responders.", summary(invited_user_ids: [ "U1", "U2" ])
    assert_equal "Invited 1 responder.", summary(invited_user_ids: [ "U1" ])
  end

  test "names the people who were already here rather than counting them" do
    text = summary(invited_user_ids: [ "U1" ], already_in_channel_user_ids: [ "U2" ])

    assert_includes text, "Invited 1 responder."
    assert_includes text, "<@U2> is already in this channel."
  end

  test "reports failures alongside what did work" do
    text = summary(invited_user_ids: [ "U1" ], failed_invites: [ { user_id: "U3", error: "cant_invite" } ])

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

  def summary(invited_user_ids: [], already_in_channel_user_ids: [], failed_invites: [])
    Slack::Messages::Invite.summary(
      IncidentInviteService::Result.new(
        invited_user_ids: invited_user_ids,
        already_in_channel_user_ids: already_in_channel_user_ids,
        failed_invites: failed_invites
      )
    )
  end
end
