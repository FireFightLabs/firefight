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
    @current_workspace = current_user && resolve_current_workspace
  end

  # Resolve through the user's memberships so session[:workspace_id] can never
  # grant access to a workspace they don't belong to. Falls back to the most
  # recently joined membership (session is fresh, or points at a workspace they
  # have since left) and self-heals the session.
  def resolve_current_workspace
    workspace = current_user.workspaces.find_by(id: session[:workspace_id]) ||
                current_user.workspace_memberships.order(joined_at: :desc).first&.workspace
    session[:workspace_id] = workspace.id if workspace && session[:workspace_id] != workspace.id
    workspace
  end

  def current_membership
    return @current_membership if defined?(@current_membership)

    @current_membership = current_user && current_workspace &&
      current_workspace.workspace_memberships.find_by(user: current_user)
  end

  def user_signed_in?
    current_user.present?
  end

  def require_authentication
    return redirect_unauthenticated unless user_signed_in?

    Current.principal = current_membership
  end

  # Settings mutations and credential reads are admin territory; responders
  # keep full incident access through Slack and the app regardless.
  def require_admin!
    return if current_membership&.admin_access?

    redirect_to dashboard_path, alert: "You need admin access to manage workspace settings"
  end

  def redirect_unauthenticated
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
