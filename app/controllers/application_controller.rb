class ApplicationController < ActionController::Base
  helper_method :current_user, :current_workspace, :user_signed_in?

  before_action { Current.trace_id = request.request_id }

  around_action do |_, action|
    payload = {}
    payload[:user_id] = current_user.id if current_user
    payload[:workspace_id] = current_workspace.id if current_workspace
    logger.tagged(payload) { action.call }
  end

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def current_workspace
    @current_workspace ||= Workspace.find_by(id: session[:workspace_id]) if session[:workspace_id]
  end

  def user_signed_in?
    current_user.present?
  end

  def require_authentication
    unless user_signed_in?
      redirect_to login_path, alert: "Please sign in to continue"
    end
  end

  def claimed_invite_code
    id = session[:invite_code_id]
    return unless id

    invite_code = InviteCode.find_by(id: id)
    return invite_code if invite_code&.active?

    session.delete(:invite_code_id)
    nil
  end
end
