# Interstitial pages between OIDC sign-in and dashboard:
#   - invite_code: new workspace installer needs to claim an invite before install
#   - install:     claimed, ready to add Firefight to Slack
#   - welcome:     first-install confirmation (letter from founder)
class OnboardingController < InertiaController
  def invite_code
    return redirect_to(login_path) if session[:pending_team_id].blank?
    return redirect_to(onboarding_install_path) if claimed_invite_code.present?

    render inertia: "onboarding/invite-code", props: {
      teamName: session[:pending_team_name]
    }
  end

  def install
    return redirect_to(login_path) if session[:pending_team_id].blank?
    return redirect_to(onboarding_invite_code_path) if claimed_invite_code.blank?

    render inertia: "onboarding/install", props: {
      teamName: session[:pending_team_name]
    }
  end

  # show_welcome_note is set in the auth callback on first install only and is
  # consumed here so the founder's letter renders exactly once. Direct visits
  # after onboarding (or refreshes) fall through to the dashboard.
  def welcome
    return redirect_to(login_path) unless user_signed_in?
    return redirect_to(dashboard_path) unless session.delete(:show_welcome_note)

    render inertia: "onboarding/welcome", props: {
      userName: current_user.name,
      workspaceName: current_workspace.name
    }
  end
end
