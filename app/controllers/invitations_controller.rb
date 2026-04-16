# Magic-link landing page for workspace invitations + admin CRUD.
#
# - GET  /invitations/:signed_id  — recipient lands here from email, kicks off OIDC
# - POST /app/settings/invitations — admin creates an invite, mailer sends link
# - DELETE /app/settings/invitations/:id — admin revokes a pending invite
class InvitationsController < ApplicationController
  before_action :require_authentication, only: [ :create, :destroy ]
  before_action :require_admin_or_owner,  only: [ :create, :destroy ]

  def show
    invitation = Invitation.find_signed(params[:signed_id], purpose: :workspace_invite)

    unless invitation && invitation.redeemed_at.nil? && invitation.expires_at > Time.current
      flash[:alert] = "This invitation link is invalid or has expired. Ask your admin for a new one."
      return redirect_to login_path
    end

    session[:pending_invitation_id] = invitation.id
    redirect_to "/auth/slack_openid"
  end

  def create
    invitation = current_workspace.invitations.create!(
      email: params.require(:email),
      invited_by: current_membership
    )
    InvitationMailer.invite(invitation).deliver_later
    redirect_to settings_members_path, notice: "Invitation sent to #{invitation.email}."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_members_path, inertia: { errors: e.record.errors.to_hash }
  end

  def destroy
    current_workspace.invitations.pending.find(params[:id]).destroy!
    redirect_to settings_members_path, notice: "Invitation revoked."
  end

  private

  def current_membership
    current_workspace.workspace_memberships.find_by!(user: current_user)
  end

  def require_admin_or_owner
    membership = current_membership
    return if membership.owner_role? || membership.admin_role?

    redirect_to settings_members_path, alert: "Only admins can manage invitations."
  end
end
