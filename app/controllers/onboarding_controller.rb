# Interstitial pages between OIDC sign-in and dashboard:
#   - install: workspace doesn't exist for this team, user can choose to install Firefight
#   - welcome: first-install confirmation (letter from founder)
class OnboardingController < InertiaController
  def install
    # Pulled from session by the OIDC handler; if missing, drop to login.
    return redirect_to(login_path) if session[:pending_team_id].blank?

    render inertia: "onboarding/install", props: {
      teamName: session[:pending_team_name],
      teamId: session[:pending_team_id]
    }
  end

  def welcome
    return redirect_to(login_path) unless user_signed_in?

    render inertia: "onboarding/welcome", props: {
      userName: current_user.name,
      workspaceName: current_workspace.name
    }
  end
end
