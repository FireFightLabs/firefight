# Renders the two interstitial pages between OIDC sign-in and dashboard:
#   - install: workspace doesn't exist, user can choose to install Firefight
#   - needs_invite: workspace exists, user isn't a member, no pending invite
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
    # return redirect_to(dashboard_path) unless session.delete(:show_welcome_note)

    render inertia: "onboarding/welcome", props: {
      userName: current_user.name,
      workspaceName: current_workspace.name
    }
  end

  def needs_invite
    render inertia: "onboarding/needs_invite", props: {
      teamName: params[:team]
    }
  end
end
