class InvitationMailer < ApplicationMailer
  def invite(invitation)
    @invitation = invitation
    @workspace  = invitation.workspace
    @inviter    = invitation.invited_by.user
    @link       = invitation_url(
      signed_id: invitation.signed_id(expires_in: Invitation::DEFAULT_TTL, purpose: :workspace_invite)
    )

    mail(
      to: invitation.email,
      from: ENV.fetch("MAIL_FROM", "Firefight <noreply@firefight.app>"),
      subject: "You're invited to join #{@workspace.name} on Firefight"
    )
  end
end
