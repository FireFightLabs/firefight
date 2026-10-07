module Auth
  # An invitation's link. Opening it only shows a button, since mail scanners fetch every link, and the POST behind it
  # signs the person in and seats them in the workspace.
  class InvitationsController < InertiaController
    include SignInSession

    EXPIRED_MESSAGE = "That invitation has expired, was already used or was taken back. Ask whoever invited you to send it again.".freeze

    skip_before_action :block_inaccessible_workspace
    skip_before_action :require_authentication

    def show
      invitation = LoginToken.find_usable(params[:token], purpose: LoginToken::INVITE)&.workspace_invitation
      invitation = nil unless invitation&.pending?

      render inertia: "login/invitation", props: {
        token: params[:token].to_s,
        usable: invitation.present?,
        workspaceName: invitation&.workspace&.name,
        inviterName: invitation&.invited_by&.display_name,
        email: invitation&.email,
        days: LoginToken.lifetime(LoginToken::INVITE).in_days.to_i
      }
    end

    def accept
      membership = WorkspaceInvitationService.accept(params[:token])
      return redirect_to(login_path, alert: EXPIRED_MESSAGE) unless membership

      start_session(user_id: membership.user_id, workspace_id: membership.workspace_id)
      redirect_to dashboard_path, notice: "Welcome to #{membership.workspace.name}."
    end
  end
end
