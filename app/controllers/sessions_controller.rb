class SessionsController < InertiaController
  def new
    # Redirect if already signed in
    if user_signed_in?
      redirect_to dashboard_path
      return
    end

    render inertia: "auth/login"
  end

  def destroy
    session.delete(:user_id)
    session.delete(:workspace_id)
    redirect_to root_path, notice: "Signed out successfully"
  end
end
