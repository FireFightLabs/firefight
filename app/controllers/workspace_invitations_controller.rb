# Inviting teammates by email from the Members page. Admins only, through the gateway like any workspace change.
class WorkspaceInvitationsController < InertiaController
  authorizes Ability::Action::RESOURCE_WORKSPACE, update: %i[create resend destroy]

  def create
    outcome = WorkspaceInvitationService.new(current_workspace)
      .invite(params[:emails], by: current_membership, link_url: link_url)
    return redirect_to(settings_members_path, inertia: { errors: { emails: [ outcome.error ] } }) if outcome.error

    redirect_to settings_members_path, notice: invited_notice(outcome.invitations)
  end

  def resend
    invitation = find_invitation
    WorkspaceInvitationService.new(current_workspace).resend(invitation, link_url: link_url)
    redirect_to settings_members_path, notice: "Invitation sent to #{invitation.email} again."
  rescue OptionGuards::Blocked => e
    redirect_to settings_members_path, alert: e.message
  end

  def destroy
    invitation = find_invitation
    return redirect_to(settings_members_path, alert: invitation.revoke_blocked_reason) unless invitation.revoke!

    redirect_to settings_members_path, notice: "Invitation to #{invitation.email} revoked."
  end

  private

  def find_invitation
    current_workspace.invitations.find(params[:id])
  end

  def link_url
    ->(token) { invitation_link_url(token: token) }
  end

  def invited_notice(invitations)
    return "Invitation sent to #{invitations.first.email}." if invitations.one?

    "Invitations sent to #{invitations.size} people."
  end
end
