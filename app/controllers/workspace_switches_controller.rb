class WorkspaceSwitchesController < ApplicationController
  before_action :require_authentication

  # Switch the active workspace for the session. Authorizes entry through the
  # user's memberships — a workspace_id the user doesn't belong to is rejected,
  # never written to the session. This is also the seam for per-workspace auth
  # policy: when SSO-enforced workspaces arrive, gate entry here (challenge for
  # re-auth if the session doesn't satisfy the target workspace's policy).
  def create
    workspace = current_user.workspaces.find_by(id: params[:workspace_id])

    if workspace
      session[:workspace_id] = workspace.id
      redirect_to dashboard_path
    else
      redirect_back fallback_location: dashboard_path, alert: "You don't have access to that workspace"
    end
  end
end
