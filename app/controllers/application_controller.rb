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
    return @current_user if defined?(@current_user)
    @current_user = session[:user_id] ? User.find_by(id: session[:user_id]) : nil
  end

  def current_workspace
    return @current_workspace if defined?(@current_workspace)
    @current_workspace = session[:workspace_id] ? Workspace.find_by(id: session[:workspace_id]) : nil
  end

  def user_signed_in?
    current_user.present?
  end

  def require_authentication
    return if user_signed_in?

    session[:return_to] = request.fullpath if request.get? && request.fullpath.start_with?("/app/")
    redirect_to login_path, alert: "Please sign in to continue"
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
