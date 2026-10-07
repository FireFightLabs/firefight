require "test_helper"

class WorkspaceInvitationMailerTest < ActionMailer::TestCase
  test "the invitation names the workspace and who invited, and says how long the link lasts" do
    inviter = workspace_memberships(:alice_workspace_one)
    invitation = WorkspaceInvitation.create!(
      workspace: inviter.workspace, email: "guest@example.com", invited_by: inviter, last_sent_at: Time.current
    )

    mail = WorkspaceInvitationMailer.invite(invitation, url: "https://app.example.com/auth/invitation?token=abc")

    assert_equal [ "guest@example.com" ], mail.to
    assert_equal "#{inviter.display_name} invited you to #{inviter.workspace.name} on Firefight", mail.subject
    assert_match "https://app.example.com/auth/invitation?token=abc", mail.text_part.body.to_s
    assert_match "https://app.example.com/auth/invitation?token=abc", mail.html_part.body.to_s
    assert_match "next 7 days", mail.text_part.body.to_s
  end
end
