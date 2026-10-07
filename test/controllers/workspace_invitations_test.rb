require "test_helper"

# Admins invite teammates by email, and the link signs the teammate in and seats them, with or without Slack.
class WorkspaceInvitationsTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper
  include ActiveJob::TestHelper

  setup do
    FeatureFlags.enable_globally!(FeatureFlags::SELF_SERVE_SIGNUP)
    @admin = User.create!(email: "admin@example.com", name: "Ada Admin")
    @admin_membership = Workspace.sign_up!(name: "Invite Co", user: @admin)
    @workspace = @admin_membership.workspace
    # What these cover comes after setup, which has its own tests.
    @workspace.onboarding.update!(checklist_completed_at: Time.current)
    sign_in_by_email(@admin)
  end

  test "an admin invites a teammate who has never used Firefight, and the link signs them in as a member" do
    assert_enqueued_emails 1 do
      post workspace_invitations_path, params: { emails: "New.Person@Example.com" }
    end
    assert_redirected_to settings_members_path
    assert_equal "Invitation sent to new.person@example.com.", flash[:notice]

    invitation = @workspace.invitations.pending.find_by!(email: "new.person@example.com")
    assert_equal @admin_membership, invitation.invited_by

    get settings_members_path, headers: inertia_headers
    assert_equal [ "new.person@example.com" ], inertia_props["invitations"].map { |row| row["email"] }
    assert_equal true, inertia_props["invitationsOffered"]
    assert_nil inertia_props["invitationUnavailableReason"]

    mail = delivered_to("new.person@example.com")
    assert_equal "Ada Admin invited you to Invite Co on Firefight", mail.subject
    token = token_in(mail)
    assert token

    delete logout_path
    get invitation_link_path(token: token), headers: inertia_headers
    assert_equal "login/invitation", JSON.parse(response.body)["component"]
    assert_equal true, inertia_props["usable"]
    assert_equal "Invite Co", inertia_props["workspaceName"]
    assert_equal "Ada Admin", inertia_props["inviterName"]
    assert_nil User.find_by(email: "new.person@example.com"), "opening the link alone makes nobody"

    post accept_invitation_path, params: { token: token }

    assert_redirected_to dashboard_path
    assert_equal "Welcome to Invite Co.", flash[:notice]
    person = User.find_by!(email: "new.person@example.com")
    seat = @workspace.workspace_memberships.find_by!(user: person)
    assert seat.member_role?
    assert_nil seat.platform_user_id
    assert UserIdentity.exists?(user: person, provider: UserIdentity::EMAIL)
    assert_equal person.id, session[:user_id]
    assert_equal @workspace.id, session[:workspace_id]
    assert invitation.reload.accepted_at
    assert_equal seat, invitation.membership

    delete logout_path
    post accept_invitation_path, params: { token: token }
    assert_redirected_to login_path
    assert_equal Auth::InvitationsController::EXPIRED_MESSAGE, flash[:alert]
  end

  test "someone who already has an account joins as themselves" do
    existing = users(:charlie)
    post workspace_invitations_path, params: { emails: existing.email }
    token = invitation_token_for(existing.email)

    delete logout_path
    post accept_invitation_path, params: { token: token }

    assert @workspace.workspace_memberships.exists?(user: existing)
    assert_equal existing.id, session[:user_id]
  end

  test "several addresses at once, with a toast that counts them" do
    post workspace_invitations_path, params: { emails: "one@example.com, two@example.com\nthree@example.com" }

    assert_equal "Invitations sent to 3 people.", flash[:notice]
    assert_equal 3, @workspace.invitations.pending.count
  end

  test "a bad address, an empty list or a current member is refused with a reason and sends nothing" do
    assert_no_enqueued_emails do
      post workspace_invitations_path, params: { emails: "not-an-email, ok@example.com" }
      post workspace_invitations_path, params: { emails: "  " }
      post workspace_invitations_path, params: { emails: @admin.email }
    end

    assert_equal 0, @workspace.invitations.count
  end

  test "resending closes the old link and sends a new one" do
    post workspace_invitations_path, params: { emails: "again@example.com" }
    old_token = invitation_token_for("again@example.com")
    invitation = @workspace.invitations.find_by!(email: "again@example.com")

    post resend_workspace_invitation_path(invitation)

    assert_equal "Invitation sent to again@example.com again.", flash[:notice]
    assert_nil LoginToken.find_usable(old_token, purpose: LoginToken::INVITE)
    assert_equal 1, invitation.login_tokens.usable.count
  end

  test "revoking closes the link for good" do
    post workspace_invitations_path, params: { emails: "gone@example.com" }
    token = invitation_token_for("gone@example.com")
    invitation = @workspace.invitations.find_by!(email: "gone@example.com")

    delete workspace_invitation_path(invitation)

    assert_equal "Invitation to gone@example.com revoked.", flash[:notice]
    assert invitation.reload.revoked_at
    delete logout_path
    post accept_invitation_path, params: { token: token }
    assert_redirected_to login_path
    assert_not @workspace.workspace_memberships.joins(:user).exists?(users: { email: "gone@example.com" })

    sign_in_by_email(@admin)
    post resend_workspace_invitation_path(invitation)
    assert_equal WorkspaceInvitation::REVOKED_REASON, flash[:alert]
  end

  test "a member who is not an admin cannot invite, resend or revoke" do
    member = User.create!(email: "plain@example.com", name: "Plain Member")
    @workspace.workspace_memberships.create!(user: member, role: :member, joined_at: Time.current)
    post workspace_invitations_path, params: { emails: "kept@example.com" }
    invitation = @workspace.invitations.find_by!(email: "kept@example.com")
    delete logout_path
    sign_in_by_email(member)

    assert_no_enqueued_emails do
      post workspace_invitations_path, params: { emails: "sneaky@example.com" }
      post resend_workspace_invitation_path(invitation)
    end
    delete workspace_invitation_path(invitation)

    assert_nil @workspace.invitations.find_by(email: "sneaky@example.com")
    assert_nil invitation.reload.revoked_at
  end

  test "a workspace sends a limited number of invitations an hour, resends included" do
    post workspace_invitations_path, params: { emails: "a@example.com" }
    invitation = @workspace.invitations.find_by!(email: "a@example.com")
    (WorkspaceInvitation::SENDS_PER_HOUR - 1).times { invitation.issue_link! }

    assert_no_enqueued_emails do
      post workspace_invitations_path, params: { emails: "c@example.com" }
      post resend_workspace_invitation_path(invitation)
    end
    assert_nil @workspace.invitations.find_by(email: "c@example.com")
    assert_match "can send #{WorkspaceInvitation::SENDS_PER_HOUR} an hour", flash[:alert]

    travel 61.minutes do
      sign_in_by_email(@admin)
      post workspace_invitations_path, params: { emails: "c@example.com" }
      assert @workspace.invitations.find_by(email: "c@example.com")
    end
  end

  test "invitations wait for outgoing email" do
    SignInMethods.stubs(:email?).returns(false)

    get settings_members_path, headers: inertia_headers
    assert_equal WorkspaceInvitation::UNAVAILABLE_REASON, inertia_props["invitationUnavailableReason"]

    assert_no_enqueued_emails do
      post workspace_invitations_path, params: { emails: "nomail@example.com" }
    end
  end

  test "joining one workspace leaves another workspace's invitation to the same person open" do
    other = Workspace.sign_up!(name: "Other Co", user: users(:bob)).workspace
    post workspace_invitations_path, params: { emails: "shared@example.com" }
    mine = invitation_token_for("shared@example.com")
    theirs = WorkspaceInvitation.create!(workspace: other, email: "shared@example.com", last_sent_at: Time.current).issue_link!

    delete logout_path
    post accept_invitation_path, params: { token: mine }

    assert LoginToken.find_usable(theirs, purpose: LoginToken::INVITE)
  end

  private

  def sign_in_by_email(user)
    token = LoginToken.issue!(email: user.email)
    post consume_email_sign_in_path, params: { token: token }
  end

  # The raw token only ever exists in the email, so the test reads it from there.
  def invitation_token_for(email)
    token_in(delivered_to(email))
  end

  def delivered_to(email)
    perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob)
    ActionMailer::Base.deliveries.reverse.find { |delivered| delivered.to == [ email ] }
  end

  def token_in(mail)
    mail.text_part.body.to_s[/token=([\w-]+)/, 1]
  end
end
