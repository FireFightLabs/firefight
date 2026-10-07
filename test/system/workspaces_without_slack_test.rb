require "application_system_test_case"

class WorkspacesWithoutSlackTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    FeatureFlags.enable_globally!(FeatureFlags::SELF_SERVE_SIGNUP)
  end

  test "someone new signs in by email, names a workspace, and lands on a dashboard that waits for Slack" do
    token = LoginToken.issue!(email: "nova@example.com")
    visit email_sign_in_link_path(token: token)
    click_on "Sign in"

    assert_text "Name your workspace"
    assert_text "Is your team already on Firefight?"
    screenshot("signup-name-workspace")

    fill_in "Your name", with: "Nova Quinn"
    fill_in "Workspace name", with: "Nova Labs"
    click_on "Create workspace"

    assert_text "You're in"
    click_on "Continue to Nova Labs"

    assert_text "Connect Slack to run incidents"
    assert_button "Connect Slack"
    declare = find_button("Declare incident", disabled: true)
    declare.find(:xpath, "..").hover
    assert_text "Connect Slack first to run incidents."
    screenshot("dashboard-waiting-for-slack")

    page.current_window.resize_to(390, 844)
    assert_text "Connect Slack to run incidents"
    screenshot("dashboard-waiting-for-slack-phone")
  end

  test "the invite gate asks for a code on the name step" do
    InviteCode.stubs(:required?).returns(true)
    token = LoginToken.issue!(email: "gated@example.com")
    visit email_sign_in_link_path(token: token)
    click_on "Sign in"

    fill_in "Your name", with: "Gale Gate"
    fill_in "Workspace name", with: "Gated Co"
    fill_in "Invite code", with: "nope"
    click_on "Create workspace"

    assert_text "That invite code is invalid or expired."
    screenshot("signup-invite-code")
  end

  test "a member who is not an admin is told who can connect Slack" do
    owner = User.create!(email: "own@example.com", name: "Owner")
    workspace = Workspace.sign_up!(name: "Members Co", user: owner).workspace
    member = User.create!(email: "mem@example.com", name: "Mem Ber")
    workspace.workspace_memberships.create!(user: member, role: :member, joined_at: Time.current)
    sign_in(member, workspace)

    visit dashboard_path

    assert_text "Ask a workspace admin to connect it."
    assert_no_button "Connect Slack"
  end

  test "an admin invites teammates, sees them pending, and revokes one after confirming" do
    admin = User.create!(email: "ada@example.com", name: "Ada Admin")
    workspace = Workspace.sign_up!(name: "Invite Co", user: admin).workspace
    sign_in(admin, workspace)

    visit settings_members_path
    assert_text "Invite teammates by email."
    click_on "Invite people"
    fill_in "Email addresses", with: "sam@example.com, kim@example.com"
    screenshot("members-invite-dialog")
    click_on "Send invitations"

    assert_text "Invitations sent to 2 people."
    assert_text "Pending invitations"
    assert_text "sam@example.com"
    assert_text "kim@example.com"
    screenshot("members-pending-invitations")

    within(:xpath, "//tr[td[contains(., 'kim@example.com')]]") { click_on "Invitation actions" }
    find("[role='menuitem']", text: "Revoke").click
    assert_text "Revoke invitation?"
    screenshot("members-revoke-confirm")
    within("[role='dialog']") { click_on "Revoke" }

    assert_text "Invitation to kim@example.com revoked."
    assert_no_selector "td", text: "kim@example.com"
    assert_selector "td", text: "sam@example.com"
  end

  test "an invitee opens the link, joins, and is signed in" do
    admin = User.create!(email: "inviter@example.com", name: "Ivy Inviter")
    membership = Workspace.sign_up!(name: "Joinable Co", user: admin)
    invitation = membership.workspace.invitations.create!(email: "joiner@example.com", invited_by: membership, last_sent_at: Time.current)
    token = invitation.issue_link!

    visit invitation_link_path(token: token)
    assert_text "Join Joinable Co"
    assert_text "Ivy Inviter invited you"
    screenshot("invitation-accept")
    click_on "Join Joinable Co"

    assert_text "Welcome to Joinable Co."
    assert_text "Connect Slack to run incidents"
  end

  private

  def screenshot(name)
    page.save_screenshot(Rails.root.join("tmp/screenshots/#{name}.png").to_s)
  end
end
