class InviteCodesController < ApplicationController
  def create
    invite_code = InviteCode.find_active_by_code(params[:code])

    unless invite_code
      session.delete(:invite_code_id)
      return redirect_to login_path, alert: "That invite code is invalid or expired."
    end

    session[:invite_code_id] = invite_code.id
    redirect_to login_path, notice: "Invite code accepted. You can continue with Slack."
  end
end
