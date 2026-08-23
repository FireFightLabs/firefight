class SessionsController < InertiaController
  # Login and logout must work for a suspended workspace's users.
  skip_before_action :block_suspended_workspace
  skip_before_action :require_authentication
  def new
    if user_signed_in?
      redirect_to dashboard_path
      return
    end

    render inertia: "login/index"
  end

  def destroy
    reset_session
    redirect_to root_path, notice: "Signed out successfully"
  end
end
