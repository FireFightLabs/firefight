class WorkspaceSwitchesController < ApplicationController
  before_action :require_authentication

  # Only the user's own memberships qualify, so a foreign workspace_id is never written
  # to the session. Per-workspace auth policy (SSO re-auth) would also go here.
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
