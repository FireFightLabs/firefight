class InviteCodesController < ApplicationController
  def create
    return redirect_to(login_path) if session[:pending_team_id].blank?

    invite_code = InviteCode.find_active_by_code(params[:code])

    unless invite_code
      session.delete(:invite_code_id)
      return redirect_to onboarding_invite_code_path, alert: "That invite code is invalid or expired."
    end

    session[:invite_code_id] = invite_code.id
    redirect_to onboarding_install_path, notice: "Invite code accepted. You can install Firefight now."
  end
end
