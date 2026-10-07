class WorkspaceInvitationMailer < ApplicationMailer
  def invite(invitation, url:)
    @url = url
    @workspace_name = invitation.workspace.name
    @inviter_name = invitation.invited_by&.display_name
    @days = LoginToken.lifetime(LoginToken::INVITE).in_days.to_i
    subject = @inviter_name ? "#{@inviter_name} invited you to #{@workspace_name} on Firefight" : "You are invited to #{@workspace_name} on Firefight"
    mail(to: invitation.email, subject: subject)
  end
end
