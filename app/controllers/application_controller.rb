class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :current_user, :current_workspace, :user_signed_in?

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
end
