class SessionsController < InertiaController
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
